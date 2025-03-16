{
  description = "A flake for installing NordVPN on NixOS";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
  };

  outputs = { self, nixpkgs, ... }:
  let
    system = "x86_64-linux";
    pkgs = import nixpkgs {
      inherit system;
      config = {
        allowUnfreePredicate = pkg: builtins.elem (nixpkgs.lib.getName pkg) [
          "nordvpn"
        ];
      };
    };
  in
  {
    packages.${system} = {
      nordvpn = pkgs.stdenv.mkDerivation rec {
        pname = "nordvpn";
        version = "3.20.0";

        src = pkgs.fetchurl {
          url = "https://repo.nordvpn.com/deb/nordvpn/debian/pool/main/n/nordvpn/nordvpn_3.20.0_amd64.deb";
          sha256 = "0fq0zfygn9disi2d1h61xg7qskbb0snhymdsmslm1zzd6c4x5wfz";
        };

        nativeBuildInputs = with pkgs; [ dpkg patchelf makeWrapper ];

        buildInputs = with pkgs; [
          glibc
          libgcc
          systemd
          iptables
          iproute2
          procps
          libxml2
          zlib
          openssl
          sqlite
        ];

        unpackPhase = "dpkg-deb -x $src .";

        installPhase = ''
          mkdir -p $out/bin $out/lib/nordvpn $out/share
          if [ -d usr/bin ]; then cp -r usr/bin/* $out/bin/; fi
          if [ -d usr/sbin ]; then cp -r usr/sbin/* $out/bin/; fi
          if [ -d usr/lib/nordvpn ]; then cp -r usr/lib/nordvpn/* $out/lib/nordvpn/; fi
          if [ -d usr/share ]; then cp -r usr/share/* $out/share/; fi

          # Debug RPATH
          echo "RPATH being set to: $out/lib/nordvpn:${pkgs.lib.makeLibraryPath buildInputs}"

          # Patch binaries with RPATH
          for bin in $out/bin/nordvpn $out/bin/nordvpnd; do
            if [ -f "$bin" ]; then
              patchelf --set-interpreter "$(cat $NIX_CC/nix-support/dynamic-linker)" "$bin"
              patchelf --set-rpath "$out/lib/nordvpn:${pkgs.lib.makeLibraryPath buildInputs}" "$bin"
            fi
          done

          # Wrap programs for PATH and LD_LIBRARY_PATH
          wrapProgram $out/bin/nordvpn \
            --prefix PATH : "${pkgs.lib.makeBinPath [ pkgs.iptables pkgs.iproute2 pkgs.procps ]}" \
            --prefix LD_LIBRARY_PATH : "${pkgs.lib.makeLibraryPath buildInputs}"

          wrapProgram $out/bin/nordvpnd \
            --prefix PATH : "${pkgs.lib.makeBinPath [ pkgs.iptables pkgs.iproute2 pkgs.procps ]}" \
            --prefix LD_LIBRARY_PATH : "${pkgs.lib.makeLibraryPath buildInputs}"
        '';

        meta = with pkgs.lib; {
          description = "NordVPN CLI client";
          homepage = "https://nordvpn.com";
          license = licenses.unfree;
          platforms = platforms.linux;
          maintainers = [];
        };
      };

      default = self.packages.${system}.nordvpn;
    };

    nixosModules.nordvpn = { config, lib, ... }: {
      options.services.nordvpn.enable = lib.mkEnableOption "NordVPN service";

      config = lib.mkIf config.services.nordvpn.enable {
        environment.systemPackages = [ self.packages.${system}.nordvpn ];

        users.users.nordvpn = {
          isSystemUser = true;
          group = "nordvpn";
          description = "NordVPN daemon user";
        };
        users.groups.nordvpn = {};

        systemd.services.nordvpnd = {
          description = "NordVPN Daemon";
          after = [ "network.target" ];
          wantedBy = [ "multi-user.target" ];
          serviceConfig = {
            ExecStart = "${self.packages.${system}.nordvpn}/bin/nordvpnd";
            Restart = "always";
            User = "nordvpn";
            Group = "nordvpn";
            StateDirectory = "nordvpn";
            CapabilityBoundingSet = "CAP_NET_ADMIN CAP_NET_RAW";
            AmbientCapabilities = "CAP_NET_ADMIN CAP_NET_RAW";
          };
        };
      };
    };
  };
}
