{
  description = "Build Android (AOSP) using Nix";

  inputs = {
    #nixpkgs.url = "github:NixOS/nixpkgs/nixos-22.11";
    nixpkgs.url = "github:Princemachiavelli/nixpkgs/jhoffer-23.05";
    #nixpkgsUnstable.url = "github:NixOS/nixpkgs/nixos-unstable";
    androidPkgs.url = "github:tadfisher/android-nixpkgs/stable";
    androidPkgs.inputs.nixpkgs.follows = "nixpkgs";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = { self, nixpkgs, flake-utils, androidPkgs, ... }@inputs:
    {
      nixosModule = import ./nixos; # Contains all robotnix nixos modules
      nixosModules.attestation-server = import ./nixos/attestation-server/module.nix;
      overlays.default = import ./pkgs/default.nix { inherit inputs; };
      defaultTemplate = {
        path = ./template;
        description = "A basic robotnix configuration";
      };
    } // (with flake-utils.lib; eachSystem [ system.x86_64-linux ] (system:
    let
      pkgs = import nixpkgs {
        inherit system self;
        config = {
          allowUnfree = true;
          permittedInsecurePackages = [
                "python-2.7.18.6"
          ];
        };
        overlays = [
          self.overlays.default
        ];
      };
      python3-local = (pkgs.python311.withPackages (p: with p; [ mypy flake8 pytest ]));
      
      lib.robotnixSystem = configuration: import ./default.nix {
          inherit configuration pkgs;
      };
      
      exampleImages = (pkgs.lib.listToAttrs (map
        (device: {
          name = device;
          value = lib.robotnixSystem {
            inherit device;
            flavor = "grapheneos";
            apv.enable = false;
            #adevtool.hash = "sha256-ea/N1dTv50w7r2X2XKIunNxJmveVjfg9NomISzNWQ/E=";
            #deviceFamily = "redfin";
            cts-profile-fix.enable = true;
            apps.vanadium.enable = false;
            webview.vanadium.enable = false;
            signing = {
              enable = true;
              keyStorePath = ./keys;
              sopsDecrypt = {
                enable = true;
                sopsConfig = ./.sops.yaml;
                #key = /home/jhoffer/.config/sops/age/robonix.txt;
                key = ./.keystore-private-keys.txt;
                keyType = "age";
              };
            };
          };
        }) [ "redfin" "bramble" "oriole" "raven" "bluejay" "panther" "cheetah" "tangorpro" "felix" ]));

      in rec {
      # robotnixSystem evaluates a robotnix configuration



      packages = {
        manual = (import ./docs { inherit pkgs; }).manual;
      } // (pkgs.lib.mapAttrs
        (device: robotnixSystem: robotnixSystem.config.build.debugEnterEnv)
        exampleImages);

      devShells = {
        default = pkgs.mkShell {
          name = "robotnix-scripts";
          nativeBuildInputs = with pkgs; [
            # For android updater scripts
            python3-local
            (gitRepo.override { python3 = python39; })
            nix-prefetch-git
            curl
            pup
            jq
            shellcheck
            wget

            # For chromium updater script
            python2
            cipd
            git

            cachix
          ];
          PYTHONPATH = ./scripts;
        };
      } // (pkgs.lib.mapAttrs
        (device: robotnixSystem: robotnixSystem.config.build.debugShell)
        exampleImages);
    }
  ));
}
