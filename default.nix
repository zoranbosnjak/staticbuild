{ sources ? import ./nix/sources.nix
, pkgs ? import sources.nixpkgs {}
, inShell ? null
, strip ? true
, static ? false    # build static binary
}:

let
  deps = with pkgs; [
  ];

  haskellPackages = with pkgs.haskell.lib; pkgs.haskellPackages.override {
    overrides = self: super:
      let
        fixGHC = pkg:
          if static == true
          then
            pkg.override {
              enableRelocatedStaticLibs = true;
              enableShared = false;
              enableDwarf = false;
            }
          else
            pkg;
      in {
        ghc = fixGHC super.ghc;
        buildHaskellPackages = super.buildHaskellPackages.override (oldBuildHaskellPackages: {
          ghc = fixGHC oldBuildHaskellPackages.ghc;
        });
        # haskellPackage1 = self.callPackage ./nix/myPackage1.nix { };
        # haskellPackage2 = self.callPackage ./nix/myPackage2.nix { };
        # ...
  };};

  buildExports = ''
  '';

  drv1 = haskellPackages.callCabal2nix "proj" ./. { };

  drv2 = drv1.overrideDerivation (oldAttrs: {
      src = builtins.filterSource
        (path: type:
          (type != "directory" || baseNameOf path != ".git")
          && (type != "symlink" || baseNameOf path != "result"))
        ./.;
      preBuild = buildExports;
      buildInputs = oldAttrs.buildInputs ++ deps;
  });

  drv = if static == true
    then drv2.overrideDerivation (oldAttrs: {
      configureFlags = [
          "--ghc-option=-Werror"
          "--ghc-option=-split-sections"
          "--ghc-option=-optl=-static"
          "--extra-lib-dirs=${pkgs.ncurses.override { enableStatic = true; }}/lib"
          # Static linking crud
          "--extra-lib-dirs=${pkgs.glibc.static}/lib"
          "--extra-lib-dirs=${pkgs.gmp6.override { withStatic = true; }}/lib"
          "--extra-lib-dirs=${pkgs.libffi.overrideAttrs (old: { dontDisableStatic = true; })}/lib"
          # The ones below are due to GHC's runtime system
          # depending on libdw (DWARF info), which depends on
          # a bunch of compression algorithms.
          "--ghc-option=-optl=-lbz2"
          "--ghc-option=-optl=-lz"
          "--ghc-option=-optl=-lelf"
          "--ghc-option=-optl=-llzma"
          "--ghc-option=-optl=-lzstd"
          "--extra-lib-dirs=${pkgs.zlib.static}/lib"
          "--extra-lib-dirs=${(pkgs.xz.override { enableStatic = true; }).out}/lib"
          "--extra-lib-dirs=${(pkgs.zstd.override { enableStatic = true; }).out}/lib"
          "--extra-lib-dirs=${(pkgs.bzip2.override { enableStatic = true; }).out}/lib"
          "--extra-lib-dirs=${(pkgs.elfutils.overrideAttrs (old: { dontDisableStatic= true; })).out}/lib"
        ] ++ pkgs.lib.optionals (!strip) [
          "--disable-executable-stripping"
        ];
      })
    else drv2;


  env = haskellPackages.shellFor {
    packages = p: with p; [
      drv
    ];

    buildInputs = with haskellPackages; deps ++ [
    ];

    shellHook = buildExports;
  };

in
  if inShell == false
    then drv
    else if pkgs.lib.inNixShell then env else drv

