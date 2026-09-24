{ config, pkgs, lib, ... }:
# ─────────────────────────────────────────────────────────────────────────────
# rice.nix — "hacking-ready + surprise-awesome" console for x220.
# Opt-in via `gnomenav.rice.enable = true` (set in hosts/x220/default.nix).
# Everything here is declarative: shell, prompt, editor, TUI eye-candy, and a
# full offensive-security toolkit. Nothing imperative, nothing that drifts.
#
# GATE: this adds a LARGE package closure (metasploit, treesitter grammars,
# wireless/crack tools). It has NOT been dry-built (no nix on the Mac, no repo
# flake.lock). Before switching x220:
#     nix build .#nixosConfigurations.x220.config.system.build.toplevel --dry-run
# If nixpkgs-25.05 renamed/dropped any attr below, eval fails naming it — drop
# that one line and re-run. Banked method: dry-build > flake check.
# ─────────────────────────────────────────────────────────────────────────────
let
  cfg = config.gnomenav.rice;

  # Modern CLI replacements + dev TUIs.
  modernCli = with pkgs; [
    eza bat fd ripgrep fzf zoxide delta dust duf procs bottom
    gping doggo xh httpie jq yq-go yazi ncdu tldr hyperfine tokei
    lazygit gitui git-absorb onefetch entr direnv sd choose
  ];

  # Terminal eye-candy — the "surprise awesome" layer.
  eyeCandy = with pkgs; [
    fastfetch cmatrix pipes-rs cbonsai tty-clock asciiquarium
    cowsay lolcat figlet toilet no-more-secrets hollywood nyancat
  ];

  # Offensive / netsec lab — the "hacking ready" layer.
  # NOTE: nixpkgs names the THC password cracker `thc-hydra` (`hydra` is the CI
  # server). searchsploit ships in `exploitdb`. tshark ships in `wireshark-cli`.
  netRecon = with pkgs; [
    nmap masscan tcpdump wireshark-cli termshark socat netcat-gnu
    mtr iperf3 nethogs iftop bandwhich arp-scan dnsutils whois
    traceroute bettercap ettercap tcpflow mitmproxy proxychains-ng
  ];
  webAudit = with pkgs; [
    nikto gobuster ffuf sqlmap wfuzz dirb whatweb wpscan sslscan nuclei
  ];
  cracking = with pkgs; [
    hashcat john thc-hydra medusa ncrack crunch cewl hashid hashcat-utils
  ];
  wireless = with pkgs; [
    aircrack-ng hcxtools hcxdumptool kismet wifite2 macchanger
  ];
  reForensics = with pkgs; [
    metasploit radare2 binwalk foremost steghide exiftool exploitdb
  ];
  osint = with pkgs; [
    theharvester recon-ng dnsrecon dnsenum amass
  ];
in
{
  options.gnomenav.rice.enable =
    lib.mkEnableOption "ricing: fish/starship, nvim IDE, TUI eye-candy, offensive-security toolkit";

  config = lib.mkIf cfg.enable {
    # ── Shell: fish as z's login shell, starship prompt everywhere ──────────
    programs.fish.enable = true;
    users.users.z.shell = pkgs.fish;

    programs.starship = {
      enable = true;
      settings = {
        add_newline = true;
        palette = "catppuccin_mocha";
        # Powerline prompt. Nerd-font glyphs () render in an SSH terminal with
        # a Nerd Font; the bare Linux console (getty) shows placeholder boxes —
        # harmless, and this box is normally driven over SSH / tmux.
        format = lib.concatStrings [
          "[](lavender)$hostname[](bg:surface1 fg:lavender)"
          "$directory[](fg:surface1 bg:surface0)$git_branch$git_status"
          "[](fg:surface0)$cmd_duration$line_break$character"
        ];
        character = {
          success_symbol = "[❯](bold green)";
          error_symbol = "[❯](bold red)";
          vimcmd_symbol = "[❮](bold yellow)";
        };
        hostname = {
          ssh_only = false;
          style = "bg:lavender fg:crust";
          format = "[ $hostname ]($style)";
        };
        directory = {
          style = "bg:surface1 fg:text";
          format = "[ $path ]($style)";
          truncation_length = 4;
          truncate_to_repo = true;
        };
        git_branch = { symbol = " "; style = "bg:surface0 fg:mauve"; format = "[ $symbol$branch ]($style)"; };
        git_status = { style = "bg:surface0 fg:red"; format = "[$all_status$ahead_behind ]($style)"; };
        cmd_duration = { min_time = 500; style = "fg:yellow"; format = " [ $duration]($style)"; };
        palettes.catppuccin_mocha = {
          crust = "#11111b";
          surface0 = "#313244";
          surface1 = "#45475a";
          text = "#cdd6f4";
          lavender = "#b4befe";
          mauve = "#cba6f7";
          red = "#f38ba8";
          yellow = "#f9e2af";
        };
      };
    };

    # Interactive greeting + tool inits (fish). Aliases below feed fish too.
    programs.fish.interactiveShellInit = ''
      set -g fish_greeting ""
      ${pkgs.fastfetch}/bin/fastfetch
      ${pkgs.zoxide}/bin/zoxide init fish | source
      ${pkgs.fzf}/bin/fzf --fish | source
    '';
    # bash fallback still gets fastfetch + tool hooks.
    programs.bash.interactiveShellInit = ''
      ${pkgs.fastfetch}/bin/fastfetch
      eval "$(${pkgs.zoxide}/bin/zoxide init bash)"
      source ${pkgs.fzf}/share/fzf/key-bindings.bash
      source ${pkgs.fzf}/share/fzf/completion.bash
    '';

    environment.shellAliases = {
      ls = "eza --icons --group-directories-first";
      ll = "eza -la --icons --git --group-directories-first";
      la = "eza -a --icons";
      lt = "eza --tree --level=2 --icons";
      cat = "bat --paging=never";
      du = "dust";
      df = "duf";
      ps = "procs";
      top = "btop";
      cd = "z";              # zoxide
      g = "lazygit";
      ff = "fastfetch";
      ports = "ss -tulpn";
      myip = "curl -s ifconfig.me";
    };

    # ── Editor: neovim as a real IDE (declarative plugin set) ───────────────
    programs.neovim = {
      enable = true;
      defaultEditor = true;
      viAlias = true;
      vimAlias = true;
      configure = {
        customRC = ''
          set number relativenumber
          set expandtab shiftwidth=2 tabstop=2 smartindent
          set ignorecase smartcase termguicolors mouse=a
          set clipboard=unnamedplus scrolloff=8 updatetime=200 signcolumn=yes
          let mapleader = " "
          lua << EOF
            require("catppuccin").setup({ flavour = "mocha" })
            vim.cmd.colorscheme("catppuccin")
            require("lualine").setup({ options = { theme = "catppuccin", globalstatus = true } })
            require("nvim-tree").setup()
            require("gitsigns").setup()
            require("Comment").setup()
            require("nvim-autopairs").setup()
            require("ibl").setup()
            require("which-key").setup()
            require("nvim-treesitter.configs").setup({ highlight = { enable = true } })
            local t = require("telescope.builtin")
            vim.keymap.set("n", "<leader>ff", t.find_files, { desc = "find files" })
            vim.keymap.set("n", "<leader>fg", t.live_grep,  { desc = "grep" })
            vim.keymap.set("n", "<leader>fb", t.buffers,    { desc = "buffers" })
            vim.keymap.set("n", "<leader>e", ":NvimTreeToggle<CR>", { silent = true, desc = "file tree" })
          EOF
        '';
        packages.jarvis.start = with pkgs.vimPlugins; [
          catppuccin-nvim
          lualine-nvim
          nvim-web-devicons
          telescope-nvim
          plenary-nvim
          (nvim-treesitter.withAllGrammars)
          nvim-tree-lua
          gitsigns-nvim
          comment-nvim
          nvim-autopairs
          indent-blankline-nvim
          which-key-nvim
        ];
      };
    };

    # ── tmux: sane defaults + catppuccin ────────────────────────────────────
    programs.tmux = {
      enable = true;
      clock24 = true;
      keyMode = "vi";
      terminal = "tmux-256color";
      historyLimit = 50000;
      extraConfig = ''
        set -g mouse on
        set -g base-index 1
        setw -g pane-base-index 1
        set -g renumber-windows on
        set -sg escape-time 10
        bind r source-file /etc/tmux.conf \; display "reloaded"
        bind | split-window -h -c "#{pane_current_path}"
        bind - split-window -v -c "#{pane_current_path}"
      '';
      plugins = with pkgs.tmuxPlugins; [ sensible yank catppuccin ];
    };

    # ── Packet capture without root (dumpcap wrapper + wireshark group) ─────
    programs.wireshark = { enable = true; package = pkgs.wireshark-cli; };
    users.users.z.extraGroups = [ "wireshark" ];

    # ── SSH login banner ────────────────────────────────────────────────────
    users.motd = ''

        ██╗  ██╗██████╗ ██████╗  ██████╗
        ╚██╗██╔╝╚════██╗╚════██╗██╔═████╗
         ╚███╔╝  █████╔╝ █████╔╝██║██╔██║
         ██╔██╗ ██╔═══╝ ██╔═══╝ ████╔╝██║
        ██╔╝ ██╗███████╗███████╗╚██████╔╝
        ╚═╝  ╚═╝╚══════╝╚══════╝ ╚═════╝

        gnomenav homelab · utility node · NixOS
        armed. type `fastfetch` · `hollywood` for a show.
    '';

    # ── The kit ─────────────────────────────────────────────────────────────
    environment.systemPackages =
      modernCli ++ eyeCandy
      ++ netRecon ++ webAudit ++ cracking ++ wireless ++ reForensics ++ osint;
  };
}
