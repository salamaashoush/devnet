{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    flake-utils.url = "github:numtide/flake-utils";
    devenv.url = "github:kadena-io/devenv/devnet-setup";
    chainweb-node.url = "github:kadena-io/chainweb-node/edmund/fast-devnet";
    chainweb-node-l2.url = "github:kadena-io/chainweb-node/edmund/l2-spv-poc";
    chainweb-data = {
      url = "github:kadena-io/chainweb-data/";
      inputs.nixpkgs.follows = "chainweb-node/nixpkgs";
      inputs.haskellNix.follows = "chainweb-node/haskellNix";
    };
    chainweb-mining-client = {
      url = "github:kadena-io/chainweb-mining-client/enis/update-to-flakes-and-haskellNix";
      inputs.haskellNix.follows = "chainweb-node/haskellNix";
      inputs.nixpkgs.follows = "chainweb-node/nixpkgs";
    };
    nix-exe-bundle = { url = "github:3noch/nix-bundle-exe"; flake = false; };
  };

  outputs = { self
            , nixpkgs
            , devenv
            , ... } @ inputs:
    inputs.flake-utils.lib.eachDefaultSystem (system:
      let common-overlay = (self: super: {
            chainweb-data = bundle inputs.chainweb-data.packages.${system}.default;
            chainweb-mining-client = bundle inputs.chainweb-mining-client.packages.${system}.default;
          });
          l1-overlay = (self: super: {
            chainweb-node = bundle inputs.chainweb-node.packages.${system}.default;
          });
          l2-overlay = (self: super: {
            chainweb-node = bundle inputs.chainweb-node-l2.packages.${system}.default;
          });
          pkgs = nixpkgs.legacyPackages.${system};
          l1-pkgs = import nixpkgs { inherit system; overlays = [ common-overlay l1-overlay ]; };
          l2-pkgs = import nixpkgs { inherit system; overlays = [ common-overlay l2-overlay ]; };
          bundle = pkgs.callPackage inputs.nix-exe-bundle {};
          modules = [
            modules/chainweb-data.nix
            modules/chainweb-node.nix
            modules/chainweb-mining-client.nix
            modules/http-server.nix
            modules/ttyd.nix
            modules/landing-page/module.nix
            ({config, ...}: {
              services.ttyd.enable = true;
              # https://devenv.sh/reference/options/
              process.implementation = "process-compose";
              devenv.root = ".";
            })
          ];
          mkFlake = pkgs: import ./mkDevnetFlake.nix { inherit pkgs nixpkgs devenv modules; };
          l1-flake = mkFlake l1-pkgs;
          l2-flake = mkFlake l2-pkgs;
      in rec {
        packages = rec {
          default = l1-flake.packages.default;
          l2 = l2-flake.packages.default;
          container = l1-flake.container;
          container-l2 = l2-flake.container;
          landing-page = l1-flake.packages.landing-page;
        };

        apps = {
          default = l1-flake.apps.default;
          l2 = l2-flake.apps.default;
          develop-page = {
            type = "app";
            program = (import ./lib/develop-page.nix {inherit pkgs;}).outPath;
          };
        };

        devShells = {
          default = l1-flake.devShells.default;
          l2 = l2-flake.devShells.default;
        };
      }
    );
}
