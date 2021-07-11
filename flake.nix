{
  description = "Golden tests for command-line interfaces.";

  inputs.flake-utils.url = github:numtide/flake-utils;
  inputs.idris = {
    url = github:idris-lang/Idris2;
    inputs.nixpkgs.follows = "nixpkgs";
    inputs.flake-utils.follows = "flake-utils";
  };

  outputs = { self, nixpkgs, idris, flake-utils }: flake-utils.lib.eachSystem ["x86_64-linux"] (system:
    let
      npkgs = import nixpkgs { inherit system; };
      idrisPkgs = idris.packages.${system};
      buildIdris = idris.buildIdris.${system};
      pkgs = (buildIdris {
        projectName = "replica";
        src = ./.;
        idrisLibraries = [];
      }) ;
    in rec {
      packages = pkgs // idrisPkgs;
      defaultPackage = pkgs.build.overrideAttrs(oa: {
        buildPhase = ''
          echo "Hello world"
          make src/Replica/Version.idr
          idris2 --build replica.ipkg
        '';
      });
      devShell = npkgs.mkShell {
        buildInputs = [ idrisPkgs.idris2 npkgs.rlwrap ];
        shellHook = ''
          alias idris2="rlwrap -s 1000 idris2 --no-banner"
        '';
      };
    }
  );
}
