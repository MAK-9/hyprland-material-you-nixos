{
  description = "Build-only flake for custom Hyprland setup (Hypryou)";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.05";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = { self, nixpkgs, flake-utils, ... }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = import nixpkgs {
          inherit system;
          config.allowUnfree = true;
        };
        pythonEnv = pkgs.python313.withPackages (ps: with ps; [
          setuptools cython pygobject3 pillow pycairo python-pam pywayland materialyoucolor
        ]);
        buildInputs = with pkgs; [
          # Required runtime/build tools
          gcc
          bash
          coreutils
          pkg-config
          gtk4

          # Python build deps
          pythonEnv

          # System deps
          gtk-layer-shell
          dart-sass
          astal.wireplumber
          astal.bluetooth
          material-symbols
          gobject-introspection
          hyprland
          dbus
          dbus-glib
          cairo
          libnotify
          libnma
          upower
          hyprsunset
          xdg-utils
          xdg-dbus-proxy
          xdg-desktop-portal
          xdg-desktop-portal-gtk
          xdg-desktop-portal-hyprland
          polkit_gnome
          adw-gtk3
          gtk3
          glib
          greetd.greetd
          cliphist
        ];

      in {
        packages.default = pkgs.stdenv.mkDerivation {
          pname = "hypryou";
          version = "unstable";
          src = ./.;
          nativeBuildInputs = buildInputs;
          passthru.providedSessions = [ "hypryou" ];

          buildPhase = ''
            echo "[build] Setting up .hypryou structure"
            mkdir -p .hypryou/{bin,lib,share}

            export LD_LIBRARY_PATH=./.hypryou/lib/hypryou:$LD_LIBRARY_PATH
            export XDG_DATA_DIRS=./.hypryou/share/hypryou:$XDG_DATA_DIRS
            export PATH=./.hypryou/bin:$PATH

            echo "[build] Patching hardcoded /usr/lib/hypryou in hypryou-start.c"
            substituteInPlace ./build/hypryou-start.c \
              --replace '"/usr/lib/hypryou"' "\"$out/lib/hypryou\""

            echo "[build] building hypryou/"
            cd ./hypryou
            python utils_cy/setup.py build_ext --build-lib utils_cy --build-temp utils_cy/build
            rm -rf utils_cy/build
            cd ..

            echo "[build] Linking hypryou and hypryou-assets"
            cp -r ./hypryou .hypryou/lib/hypryou
            cp -r ./hypryou-assets .hypryou/share/hypryou

            echo "[build] Building hypryouctl"
            gcc -Wall -Wextra -Wpedantic -Wshadow -Wformat=2 -Wcast-align -Wconversion -Wstrict-overflow=5 -O3 -march=native -flto -fno-plt \
              ./build/client.c -o .hypryou/bin/hypryouctl

            echo "[build] Building hypryou-start"
            gcc -O3 -march=native -flto -fno-plt $(pkg-config --cflags --libs gtk4) -Wall -Wextra -Wpedantic -Wshadow -Wformat=2 -Wcast-align -Wconversion -Wstrict-overflow=5 \
              ./build/hypryou-start.c -o .hypryou/bin/hypryou-start

            echo "[build] Building hypryou-crash-dialog"
            gcc -O3 -march=native -flto -fno-plt $(pkg-config --cflags --libs gtk4) -Wall -Wextra -Wpedantic -Wshadow -Wformat=2 -Wcast-align -Wconversion -Wstrict-overflow=5 \
              ./build/crash-dialog.c -o .hypryou/bin/hypryou-crash-dialog
          '';

          installPhase = let
            hypryouSession = ''
              [Desktop Entry]
              Name=HyprYou
              Comment=Run HyprYou DE on Hyprland WM
              Exec=hyprland --config $out/share/hypryou/configs/hyprland/main.conf
              Type=Application
              DesktopNames=HyprYou
            '';
          in ''
            echo "[install] Copying .hypryou to $out"
            mkdir -p $out

            cp -r .hypryou/* $out/
            rm -rf ./.hypryou/

            echo "[install] Installing default colors-hyprland.conf template"
            mkdir -p $out/share/hypryou/colors
            cat > $out/share/hypryou/colors/colors-hyprland.conf << 'COLEOF'
$primary = rgb(6750A4)
$onPrimary = rgb(FFFFFF)
$primaryContainer = rgb(EADDFF)
$background = rgb(1C1B1F)
$surface = rgb(1C1B1F)
$onSurface = rgb(E6E1E5)
COLEOF

            echo "[install] Fixing hardcoded /usr/share/hypryou paths"
            find $out/share/hypryou/configs -name "*.conf" -exec \
              sed -i "s|/usr/share/hypryou|$out/share/hypryou|g" {} \;

            echo "[install] Wrapping hypryou-start to include Python in PATH"
            mv $out/bin/hypryou-start $out/bin/.hypryou-start-unwrapped
            cat > $out/bin/hypryou-start << WRAPEOF
#!/bin/sh
export PATH="${pythonEnv}/bin:$PATH"
export GI_TYPELIB_PATH="${pkgs.gtk4}/lib/girepository-1.0:${pkgs.gtk-layer-shell}/lib/girepository-1.0:${pkgs.astal.wireplumber}/lib/girepository-1.0:${pkgs.astal.bluetooth}/lib/girepository-1.0:${pkgs.networkmanager}/lib/girepository-1.0:${pkgs.upower}/lib/girepository-1.0"
export LD_LIBRARY_PATH="${pkgs.gtk4}/lib:${pkgs.gtk-layer-shell}/lib:${pkgs.cairo}/lib:${pkgs.glib}/lib"
exec $out/bin/.hypryou-start-unwrapped "''$@"
WRAPEOF
            chmod +x $out/bin/hypryou-start

            mkdir -p $out/share/wayland-sessions

            echo "${hypryouSession}" > $out/share/wayland-sessions/hypryou.desktop
          '';

          dontFixup = true;
        };
      });
}

