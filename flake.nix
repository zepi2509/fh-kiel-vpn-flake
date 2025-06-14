{
  description = "A fully automated Nix Flake for the FH Kiel VPN";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

  outputs = { self, nixpkgs }:
    let
      system = "x86_64-linux";
      pkgs = import nixpkgs { inherit system; };

      patchScript = ./patch-installer.sh;

      ciscoSecureClientSrc = pkgs.fetchurl {
        url = "https://www.fh-kiel.de/fileadmin/data/zentrale_it/vpn/cisco_secure_client_5.1.4.74/cisco-secure-client-linux64-5.1.4.74-predeploy-k9.tar.gz";
        sha256 = "sha256-wDS17WpNuOqt0xPnvR24iLVXbhIpWheIgz7r/CigT4s=";
      };
    in {
      overlays.default = final: prev: {
        fh-kiel-vpn = self.packages.${system}.default;
      };

      packages.${system}.default =
        let
          # Define the runtime dependencies here to make them available everywhere below
          runtimeDependencies = with pkgs; [
            cairo
            gdk-pixbuf
            glib
            gtk3
            libappindicator-gtk3
            libxml2
            networkmanager
            openssl
            stdenv.cc
            zlib
          ];
        in
        pkgs.buildFHSEnv {
          name = "fh-kiel-vpn";

          # Dependencies needed for the installer script to RUN
          buildInputs = [
            patchScript
            pkgs.bash
            pkgs.coreutils
            pkgs.gnused
            pkgs.gnutar
            pkgs.gzip
            pkgs.procps
            pkgs.glibc
            pkgs.file 
            pkgs.patchelf 
            pkgs.libxml2
            pkgs.stdenv.cc
          ];

          # Dependencies needed for the final application to LAUNCH
          targetPkgs = pkgs: runtimeDependencies;

          runScript = "/opt/cisco/secureclient/bin/vpnui";

          extraInstallCommands = ''
            set -x

            # Create all expected directories
            mkdir -p "$out/opt/cisco/secureclient"
            mkdir -p "$out/opt/cisco/anyconnect"
            mkdir -p "$out/opt/.cisco/certificates/ca"
            mkdir -p "$out/share/icons/hicolor/48x48/apps"
            mkdir -p "$out/share/icons/hicolor/64x64/apps"
            mkdir -p "$out/share/icons/hicolor/96x96/apps"
            mkdir -p "$out/share/icons/hicolor/128x128/apps"
            mkdir -p "$out/share/icons/hicolor/256x256/apps"
            mkdir -p "$out/share/icons/hicolor/512x512/apps"
            mkdir -p "$out/share/desktop-directories"
            mkdir -p "$out/share/applications"
            mkdir -p "$out/etc/xdg/menus/applications-merged"
            mkdir -p "$out/share/gnome-menus"

            local INSTALL_TMP="$TMPDIR/cisco-installer"
            mkdir -p "$INSTALL_TMP"

            tar -xzf ${ciscoSecureClientSrc} -C "$INSTALL_TMP"

            INSTALLER_SCRIPT="$(find "$INSTALL_TMP" -name "vpn_install.sh")"
            INSTALLER_DIR="$(dirname "$INSTALLER_SCRIPT")"

            # Patch the installer script to work in our environment
            cp ${patchScript} ./patch-installer.sh
            chmod +x ./patch-installer.sh
            patchShebangs ./patch-installer.sh
            ./patch-installer.sh "$INSTALLER_SCRIPT" "$out" "${pkgs.gnused}"

            chmod +x "$INSTALLER_SCRIPT"

            echo "Running patched installer script..."
            (cd "$INSTALLER_DIR" && "$INSTALLER_SCRIPT")
            echo "Installer finished laying out files."

            # --- Post-install patching and finalization ---
            echo "Patching ELF binaries to use Nix's dynamic linker..."
            local lib_path="$out/opt/cisco/secureclient/lib"
            local bin_path="$out/opt/cisco/secureclient/bin"
            # Use the 'runtimeDependencies' variable defined in the 'let' block
            local rpath="$lib_path:$bin_path:${pkgs.lib.makeLibraryPath runtimeDependencies}"

            find "$bin_path" "$lib_path" -type f -exec file {} + | grep "ELF" | cut -d: -f1 | while read -r elf_file; do
                echo "Patching RPATH for: $elf_file"
                patchelf --set-rpath "$rpath" "$elf_file"

                if file "$elf_file" | grep -q "executable"; then
                    echo "Setting interpreter for executable: $elf_file"
                    patchelf --set-interpreter "$(cat ${pkgs.stdenv.cc}/nix-support/dynamic-linker)" "$elf_file"
                fi
            done

            echo "Binaries patched. Running deferred setup commands..."

            "$bin_path/acinstallhelper" -acpolgen bd=false bdl=false rswd=false rhwd=false rrwd=false rlwd=false fm=false rpc=false rtp=false rwl=false sct=false efn=false upsu=true upcu=true upvp=true upmv=true upip=true upsp=true upscr=true uphlp=true upres=true uploc=true

            "$bin_path/manifesttool_vpn" -i "$out/opt/cisco/secureclient" "$out/opt/cisco/secureclient/ACManifestVPN.xml"

            echo "Build process complete."
          '';

          meta = with pkgs.lib; {
            description = "Cisco Secure Client for FH Kiel VPN";
            homepage = "https://www.fh-kiel.de/fh-intern/beratung-unterstuetzung-und-hilfe/it-hilfen/vpn-einwahl-in-das-campusnetz/";
            platforms = platforms.linux;
            maintainers = [ "Noah Zepner" ];
          };
        };

      apps.${system}.default = {
        type = "app";
        program = "${self.packages.${system}.default}/bin/fh-kiel-vpn";
      };
    };
}
