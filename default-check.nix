{ sources ? import ./nix/sources.nix
, packages ? import sources.nixpkgs {}
, inShell ? null
, strip ? true
, static ? true    # build static binary
}:

let
  pkgs = packages;

  haskellPackages1 = if static == true
    then pkgs.pkgsStatic.haskellPackages
    else pkgs.haskellPackages;

  haskellPackages = haskellPackages1.override {
    overrides = haskellPackagesNew: haskellPackagesOld: rec {
      # haskellPackage1 = haskellPackagesNew.callPackage ./nix/myPackage1.nix { };
      # ...
    };
  };

  drv1 = haskellPackages.callCabal2nix "test" ./. { };

  drv = drv1.overrideDerivation (oldAttrs: {
    src = builtins.filterSource
      (path: type:
           (type != "directory" || baseNameOf path != "folds")
        && (type != "symlink" || baseNameOf path != "result"))
        ./.;
    }) // { inherit env; };

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
