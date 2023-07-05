{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    systems.url = "github:nix-systems/default";
    devenv.url = "github:cachix/devenv";
    chainweb-node.url = "github:kadena-io/chainweb-node/edmund/fast-devnet";
    chainweb-data.url = "github:kadena-io/chainweb-data";
    chainweb-mining-client.url = "github:kadena-io/chainweb-mining-client/enis/update-to-flakes-and-haskellNix";
  };

  nixConfig = {
    extra-trusted-public-keys = "devenv.cachix.org-1:w1cLUi8dv3hnoSPGAuibQv+f9TZLr6cv/Hm9XgU50cw=";
    extra-substituters = "https://devenv.cachix.org";
  };

  outputs = { self
            , nixpkgs
            , devenv
            , systems
            , ... } @ inputs:
    let
      forEachSystem = nixpkgs.lib.genAttrs (import systems);
    in
    {
      packages."x86_64-linux".default = inputs.chainweb-mining-client.packages."x86_64-linux".default;
      devShells = forEachSystem
        (system:
          let
            pkgs = nixpkgs.legacyPackages.${system};
            start-chainweb-node = pkgs.writeShellScript "start-chainweb-node" ''
              chainweb-node \
              --config-file=./chainweb/config/chainweb-node.common.yaml \
              --p2p-certificate-chain-file=./chainweb/devnet-bootstrap-node.cert.pem \
              --p2p-certificate-key-file=./chainweb/devnet-bootstrap-node.key.pem \
              --p2p-hostname=bootstrap-node \
              --bootstrap-reachability=2 \
              --cluster-id=devnet-minimal \
              --p2p-max-session-count=3 \
              --mempool-p2p-max-session-count=3 \
              --known-peer-info=YNo8pXthYQ9RQKv1bbpQf2R5LcLYA3ppx2BL2Hf8fIM@bootstrap-node:1789 \
              --log-level=info \
              --enable-mining-coordination \
              --mining-public-key=f90ef46927f506c70b6a58fd322450a936311dc6ac91f4ec3d8ef949608dbf1f \
              --header-stream \
              --rosetta \
              --allowReadsInLocal \
              --database-directory=./chainweb/db \
              --disable-pow
            '';
            start-chainweb-mining-client = pkgs.writeShellScript "start-chainweb-mining-client" ''
              chainweb-mining-client \
              --public-key=f90ef46927f506c70b6a58fd322450a936311dc6ac91f4ec3d8ef949608dbf1f \
              --node=127.0.0.1:1848 \
              --worker=constant-delay \
              --constant-delay-block-time=5 \
              --thread-count=1 \
              --log-level=info \
              --no-tls
            '';
          in
          {
            default = devenv.lib.mkShell {
              inherit inputs pkgs;
              modules = [
                {
                  # https://devenv.sh/reference/options/
                  packages = [
                    inputs.chainweb-node.packages.${system}.default
                    inputs.chainweb-mining-client.packages.${system}.default
                    pkgs.nodejs-18_x
                  ];

                  services.nginx.enable = true;
                  services.nginx.httpConfig = ''
                    server {
                      listen 1337;
                      location / {
                        proxy_pass https://www.google.com;
                      }
                    }
                  '';
                  process-managers.process-compose.enable = true;
                  process.implementation = "process-compose";
                  processes.chainweb-node = {
                    exec = "${start-chainweb-node}";
                    process-compose.readiness_probe = {
                      http_get = {
                        host = "127.0.0.1";
                        scheme = "http";
                        port = 1848;
                        path = "/health-check";
                      };
                      initial_delay_seconds = 5;
                      period_seconds = 10;
                      timeout_seconds = 30;
                      success_threshold = 1;
                      failure_threshold = 10;
                    };
                  };
                  processes.chainweb-mining-client = {
                    exec = "${start-chainweb-mining-client}";
                    process-compose = {
                      depends_on.chainweb-node.condition = "process_healthy";
                    };
                  };
                }
              ];
            };
          });
    };
}
