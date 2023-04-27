{ config, lib, pkgs, ... }:
let
  inherit (lib) mkEnableOption mkIf;
in
{
  options = {
    cts-profile-fix = {
      enable = mkEnableOption "apply ProtonAOSP patches to make Safetynet CTS Profile pass";
    };
  };
  config = mkIf config.cts-profile-fix.enable {
    source.dirs."system/core".patches = [
      (pkgs.fetchpatch {
        name = "init-set-properties-for-safety-net.patch";
        sha256 = "sha256-UGfF92dkhn/eQpLexLO2GxYozKVNb0yAk5spnF4SS9s=";
        url = "https://github.com/ProtonAOSP/android_system_core/commit/3102e9e8c.patch";
      })
      # need to use this patched version of fastboot to work with the bootloader as otherwise it will
      # always see the bootloader as locked.
      (pkgs.fetchpatch {
        name = "fastboot-revert-to-A11-lock-status.patch";
        sha256 = "sha256-UnkYIPG/43XM3asTqGX9rE6JOkf8+KZUM/jFL4wjd5k=";
        url = "https://github.com/ProtonAOSP/android_system_core/commit/497ada563.patch";
      })
    ];
  };
}
