{
  description = "Golden tests for command-line interfaces.";

  inputs.flake-utils.url = github:numtide/flake-utils;
  inputs.idris = {
    url = github:idris-lang/Idris2/v0.4.0;
    inputs.nixpkgs.follows = "nixpkgs";
    inputs.flake-utils.follows = "flake-utils";
  };

  outputs = { self, nixpkgs, idris, flake-utils }: flake-utils.lib.eachDefaultSystem (system:
    let
      npkgs = import nixpkgs { inherit system; };
      idrisPkgs = idris.packages.${system};
      buildIdris = idris.buildIdris.${system};

      replica_ = buildIdris {
        projectName = "replica";
        src = ./.;
        idrisLibraries = [];
      };
      replica = replica_.build.overrideAttrs (attrs: {
        patchPhase = ''
          # I haven't tested this, might have escaped incorrectly
          sed "s/\`git describe --tags\`/v0.4.0-${self.shortRev or "dirty"}/" -i Makefile
        '';
        buildPhase = ''
          make
        '';
      });

    in rec {
      packages = replica // idrisPkgs;
      defaultPackage = replica;
      devShell = npkgs.mkShell {
        buildInputs = [ idrisPkgs.idris2 npkgs.rlwrap ];
        shellHook = ''
          alias idris2="rlwrap -s 1000 idris2 --no-banner"
        '';
      };
    }
  );
}
