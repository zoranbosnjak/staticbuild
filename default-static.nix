{ sources ? import ./nix/sources.nix
, packages ? import sources.nixpkgs {}
, inShell ? null
, withHoogle ? false
, strip ? true
, static ? false    # build static binary
}:

let
  pkgs = if static == true
    then packages.pkgsMusl.pkgsMusl
    else packages;

  deps = with pkgs; [
    which
    # ...
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
    export LC_ALL=C.UTF-8
    export GHC_BASE=$(which ghc | cut -d '/' -f-4)
  '';

  drv1 = haskellPackages.callCabal2nix "projname" ./. { };

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
        "--ghc-option=-optl=-static"
        "--disable-shared"
        "--extra-lib-dirs=${pkgs.gmp6.override { withStatic = true; }}/lib"
        "--extra-lib-dirs=${pkgs.zlib.static}/lib"
        "--extra-lib-dirs=${pkgs.libffi.overrideAttrs (old: { dontDisableStatic = true; })}/lib"
        # double-conversion temporary patch
        # This is required on nix-packages 24.05 until this patch is merged
        # https://github.com/NixOS/nixpkgs/pull/322738
        "--extra-lib-dirs=${pkgs.double-conversion.overrideAttrs(_: { cmakeFlags = [ ]; })}/lib"
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
      niv
      pkgs.cacert # needed for niv
      pkgs.nix    # needed for niv
      cabal-install
      pkgs.ghcid
      pkgs.cabal2nix
      # haskell-language-server
      # fast-tags
      # haskell-debug-adapter
      # ghci-dap
    ];

    withHoogle = withHoogle;

    shellHook = buildExports;
  };

in
  if inShell == false
    then drv
    else if pkgs.lib.inNixShell then env else drv
