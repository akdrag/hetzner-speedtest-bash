{
  description = "Hetzner Speedtest - measure download speed, latency & jitter";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = { self, nixpkgs, flake-utils }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = nixpkgs.legacyPackages.${system};
      in
      {
        packages.default = pkgs.stdenvNoCC.mkDerivation {
          pname = "hetzner-speedtest";
          version = "1.0.0";
          src = ./.;

          dontBuild = true;

          installPhase = ''
            mkdir -p $out/bin
            cp hetzner-speedtest.sh $out/bin/hetzner-speedtest
            cp hosts.json $out/bin/hosts.json
            chmod +x $out/bin/hetzner-speedtest
            patchShebangs $out/bin/hetzner-speedtest
          '';

          propagatedBuildInputs = with pkgs; [ bash curl jq bc ];

          meta = with pkgs.lib; {
            description = "CLI speedtest tool for Hetzner data centers";
            homepage = "https://github.com/hetznercloud/hetzner-speedtest-bash";
            license = licenses.mit;
            maintainers = [];
            platforms = platforms.all;
            mainProgram = "hetzner-speedtest";
          };
        };

        devShells.default = pkgs.mkShell {
          buildInputs = with pkgs; [
            bash
            curl
            jq
            bc
            shellcheck
            shfmt
          ];

          shellHook = ''
            echo "❄️  Hetzner Speedtest dev shell"
            echo "   Dependencies: curl jq bc"
            echo "   Linters:      shellcheck shfmt"
          '';
        };
      });
}
