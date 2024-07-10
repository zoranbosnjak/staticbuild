{ sources ? import ./nix/sources.nix
, packages ? import sources.nixpkgs {}
, inShell ? null
, strip ? true
, static ? true    # build static binary
}:

let
  pkgs = if static == true
    then packages.pkgsMusl.pkgsMusl
    else packages;

  haskellPackages = with pkgs.haskell.lib; pkgs.haskellPackages.override {
    overrides = self: super: {
  };};

  drv1 = haskellPackages.callCabal2nix "test" ./. { };

  drv2 = drv1.overrideDerivation (oldAttrs: {
    src = builtins.filterSource
      (path: type:
           (type != "directory" || baseNameOf path != "folds")
        && (type != "symlink" || baseNameOf path != "result"))
        ./.;
    }) // { inherit env; };

  drv = if static == true
    then drv2.overrideDerivation (oldAttrs: {
      configureFlags = [
        "--ghc-option=-optl=-static"
        "--disable-shared"
        "--extra-lib-dirs=${pkgs.gmp6.override { withStatic = true; }}/lib"
        "--extra-lib-dirs=${pkgs.zlib.static}/lib"
        "--extra-lib-dirs=${pkgs.libffi.overrideAttrs (old: { dontDisableStatic = true; })}/lib"
        ] ++ pkgs.lib.optionals (!strip) [
          "--disable-executable-stripping"
        ];
      })
    else drv2;

  env = pkgs.stdenv.mkDerivation rec {
    name = "test-devel-environment";
    buildInputs = drv1.env.nativeBuildInputs ++ [
      pkgs.cabal2nix
      pkgs.ghcid
    ];
    shellHook = ''
      export LC_ALL=C.UTF-8
      export GHC_BASE=$(which ghc | cut -d '/' -f-4)
    '';
  };

in
  if inShell == false
    then drv
    else if pkgs.lib.inNixShell then env else drv
