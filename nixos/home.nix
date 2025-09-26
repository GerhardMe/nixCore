{ system, nixpkgs, home-manager, pkgs, ... }: {

  # ------------------------------------------------------------------------------------------
  # ----------------------------------------- SETTINGS ---------------------------------------
  # ------------------------------------------------------------------------------------------

  home.stateVersion = "24.11";

  # ENV varriables
  home.sessionVariables = {
    GIT_EDITOR = "nvim";
    EDITOR = "nvim";
    BROWSER = "firefox";
    XCURSOR_THEME = "phinger-cursors-light";
  };

  # Custom directories
  xdg.userDirs = {
    enable = true;
    download = "$HOME/downloads";
    pictures = "$HOME/media/img";
    videos = "$HOME/media/vid";
    music = "$HOME/media/music";
    documents = "$HOME/workspaces";
    desktop = "$HOME/workspaces";
    templates = "$HOME/.xdgdirs/templates";
  };

  # ------------------------------------------------------------------------------------------
  # ----------------------------------------- SERVICES ---------------------------------------
  # ------------------------------------------------------------------------------------------

  # Handle hardware events
  systemd.user.services.hw-events = {
    Unit = {
      Description = "handle all hardware events";
      After = [ "graphical-session.target" ];
    };
    Service = {
      Type = "oneshot";
      ExecStart = "%h/nixCore/scripts/hardware-events.sh";
      Restart = "on-failure";
      RestartSec = 10;
      Environment = "PATH=/run/current-system/sw/bin";
      Group = "users";
    };
    Install = { WantedBy = [ "default.target" ]; };
  };

  # Sleep inhibetor service
  systemd.user.services.awake = {
    Unit = {
      Description = "Keep laptop awake (block suspend + lid close)";
      After = [ "graphical-session.target" ];
      PartOf = [ "graphical-session.target" ];
    };
    Service = {
      Type = "simple";
      ExecStart =
        "${pkgs.systemd}/bin/systemd-inhibit --what=idle:sleep:handle-lid-switch --mode=block --why='server mode' ${pkgs.coreutils}/bin/sleep infinity";
      # If you stop it, it stays stopped. No Restart.
      Environment = "PATH=/run/current-system/sw/bin";
    };
    Install = { WantedBy = [ "default.target" ]; };
  };

  # SSH watcher
  systemd.user.services.ssh-bar = {
    Unit = {
      Description = "Watch sshd journal";
      After = [ "graphical-session.target" ];
      PartOf = [ "graphical-session.target" ];
    };
    Service = {
      Type = "simple";
      ExecStart = "%h/nixCore/scripts/ssh-detect.sh";
      Restart = "always";
      RestartSec = 1;
      Environment = [
        "PATH=%h/.nix-profile/bin:/etc/profiles/per-user/%u/bin:/run/current-system/sw/bin"
        "DISPLAY=:0"
        "XDG_RUNTIME_DIR=%t"
      ];
    };
    Install = { WantedBy = [ "default.target" ]; };
  };

  # ------------------------------------------------------------------------------------------
  # ----------------------------------------- RICE -------------------------------------------
  # ------------------------------------------------------------------------------------------

  home.pointerCursor = {
    name = "phinger-cursors-light";
    package = pkgs.phinger-cursors;
    size = 32;
    gtk.enable = true;
  };

  gtk = {
    enable = true;
    iconTheme = {
      name = "Papirus-Dark";
      package = pkgs.papirus-icon-theme;
    };
  };

  # ------------------------------------------------------------------------------------------
  # ----------------------------------------- USER PROGRAMS ----------------------------------
  # ------------------------------------------------------------------------------------------

  nixpkgs.config.allowUnfree = true;
  home.packages = with pkgs; [

    # Big programs:
    slack
    spotify
    kicad-small
    discord
    freecad
    qbittorrent
    protonvpn-gui
    krita
    gimp

    # Games:
    prismlauncher # open source minecraft launcher
    steam

    # Editors:
    vscode
    obsidian
    libreoffice

    # Rice:
    unclutter
    xwallpaper
    papirus-icon-theme

    # Fun:    
    fastfetch
    neofetch
    cmatrix
    pipes
    cava
    asciiquarium-transparent
    sl
  ];

  # ------------------------------------------------------------------------------------------
  # ---------------------------------------- NEOVIM ------------------------------------------
  # ------------------------------------------------------------------------------------------

  programs.neovim = {
    enable = true;
    defaultEditor = true;
    viAlias = true;
    vimAlias = true;
  };

  # ------------------------------------------------------------------------------------------
  # ----------------------------------------- GIT --------------------------------------------
  # ------------------------------------------------------------------------------------------

  programs.git = {
    enable = true;
    userName = "Gerhard Gustavsen";
    userEmail = "gerhard.gustavsen@outlook.com";
  };

  # ------------------------------------------------------------------------------------------
  # ----------------------------------------- FIREFOX ----------------------------------------
  # ------------------------------------------------------------------------------------------

  programs = {
    firefox = {
      enable = true;
      languagePacks = [ "en-UK" "no" ];

      # ---- POLICIES ----
      # Check about:policies#documentation for options.
      policies = {
        DisableTelemetry = true;
        DisableFirefoxStudies = true;
        EnableTrackingProtection = {
          Value = true;
          Locked = true;
          Cryptomining = true;
          Fingerprinting = true;
        };
        DisablePocket = true;
        DisableFirefoxAccounts = true;
        DisableAccounts = true;
        DisableFirefoxScreenshots = true;
        OverrideFirstRunPage = "";
        OverridePostUpdatePage = "";
        DontCheckDefaultBrowser = true;
        DisplayBookmarksToolbar = "never"; # alternatives: "always" or "newtab"
        DisplayMenuBar =
          "default-off"; # alternatives: "always", "never" or "default-on"
        SearchBar = "unified"; # alternative: "separate"
        PasswordManagerEnabled = false;

        # ---- EXTENSIONS ----
        # Check about:support for extension/add-on ID strings.
        # Valid strings for installation_mode are "allowed", "blocked",
        # "force_installed" and "normal_installed".
        ExtensionSettings = {
          "*".installation_mode = "allowed";
          # uBlock Origin:
          "uBlock0@raymondhill.net" = {
            install_url =
              "https://addons.mozilla.org/firefox/downloads/latest/ublock-origin/latest.xpi";
            installation_mode = "force_installed";
          };
          # Privacy Badger:
          "jid1-MnnxcxisBPnSXQ@jetpack" = {
            install_url =
              "https://addons.mozilla.org/firefox/downloads/latest/privacy-badger17/latest.xpi";
            installation_mode = "force_installed";
          };
          # Proton Pass:
          "78272b6fa58f4a1abaac99321d503a20@proton.me" = {
            install_url =
              "https://addons.mozilla.org/firefox/downloads/latest/proton-pass/latest.xpi";
            installation_mode = "force_installed";
          };
          # Proton VPN:
          "vpn@proton.ch" = {
            install_url =
              "https://addons.mozilla.org/firefox/downloads/file/4539502/proton_vpn_firefox_extension-1.2.9.xpi";
            installation_mode = "force_installed";
          };
          # Unhook:
          "myallychou@gmail.com" = {
            install_url =
              "https://addons.mozilla.org/firefox/downloads/file/4263531/youtube_recommended_videos-1.6.7.xpi";
            installation_mode = "force_installed";
          };
          # Theme:
          "dreamer-bold-colorway@mozilla.org" = {
            install_url =
              "https://addons.mozilla.org/firefox/downloads/latest/dreamer-bold/latest.xpi";
            installation_mode = "force_installed";
          };
        };

        # ---- PREFERENCES ----
        # Check about:config for options.
        Preferences = {
          "browser.contentblocking.category" = {
            Value = "strict";
            Status = "locked";
          };
        };
      };
    };
  };

}
