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

        # Include sqlite along with other dependencies
        buildInputs = with pkgs; [
          glibc
          libgcc
          systemd
          iptables
          iproute2
          procps
          libxml2  # For libxml2.so.2
          zlib     # For libz.so.1
          openssl  # For libssl.so and libcrypto.so
          sqlite   # For libsqlite3.so
        ];

        unpackPhase = "dpkg-deb -x $src .";

        installPhase = ''
          mkdir -p $out/bin $out/lib/nordvpn $out/share
          if [ -d usr/bin ]; then cp -r usr/bin/* $out/bin/; fi
          if [ -d usr/sbin ]; then cp -r usr/sbin/* $out/bin/; fi
          if [ -d usr/lib/nordvpn ]; then cp -r usr/lib/nordvpn/* $out/lib/nordvpn/; fi
          if [ -d usr/share ]; then cp -r usr/share/* $out/share/; fi

          # Ensure all binaries have the correct interpreter and RPATH
          for bin in $out/bin/nordvpn $out/bin/nordvpnd; do
            if [ -f "$bin" ]; then
              patchelf --set-interpreter "$(cat $NIX_CC/nix-support/dynamic-linker)" "$bin"
              patchelf --set-rpath "$out/lib/nordvpn:${pkgs.lib.makeLibraryPath buildInputs}" "$bin"
            fi
          done

          # Wrap programs to ensure runtime dependencies are available
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

    nixosModules.nordvpn = { config, lib, pkgs, ... }: {
      options.services.nordvpn.enable = lib.mkEnableOption "NordVPN service";

      config = lib.mkIf config.services.nordvpn.enable {
        environment.systemPackages = [ self.packages.${system}.nordvpn ];

        systemd.services.nordvpnd = {
          description = "NordVPN Daemon";
          after = [ "network.target" ];
          wantedBy = [ "multi-user.target" ];
          serviceConfig = {
            ExecStart = "${self.packages.${system}.nordvpn}/bin/nordvpnd";
            Restart = "always";
            # Ensure /var/lib/nordvpn is created and owned by the service user
            StateDirectory = "nordvpn";
            # Run the service as a dynamic user (optional, but recommended for security)
            DynamicUser = true;
          };
        };
      };
    };
  };
}
