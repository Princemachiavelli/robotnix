{ config, lib, pkgs, ... }:
let
  inherit (lib) mkIf mkEnableOption mkOption types;
  cfg = config.adevtool;
  adevtoolPkg = pkgs.adevtool config.source.dirs."vendor/adevtool".src;
  adevtool = "${adevtoolPkg}/bin/adevtool";
  adevtoolHash = {
    "felix" = {
      "TQ3C.230605.010.C1" = "sha256-X00bRj7yC+0mvglP/Lkw16G5Ql3xogSxePvgWq9RpFM=";
    };
  };
  fetchImage = { device, buildID }:
    pkgs.stdenv.mkDerivation {
      name = "fetch-vendor-firmware";
      src = pkgs.emptyDirectory;
      installPhase = ''
        mkdir -p $out
        export HOME=$(pwd)
        ${adevtool} download $out -d ${device} -b ${buildID} -t factory ota | cat
      '';

      outputHashMode = "recursive";
      outputHashAlgo = "sha256";
      outputHash = adevtoolHash."${device}"."${buildID}";
    };
  sepolicyDirNames = lib.filter (d: lib.hasSuffix "-sepolicy" d) (lib.attrNames config.source.dirs);
  unpackPhase =
    let
      unpackDirNames = lib.filter
        (d:
          !(lib.elem d ([ "vendor/adevtool" "vendor/google_devices/${config.device}" ]))
          && !(lib.hasPrefix "kernel/android" d))
        (lib.attrNames config.source.dirs);
      unpackDirs = lib.attrVals unpackDirNames config.source.dirs;
    in
    pkgs.writeTextFile {
      name = "unpack-sources-for-adevtool";
      executable = true;
      text = ''
        mkdir -p vendor/adevtool
        mount --bind ${adevtoolPkg + /libexec/adevtool/deps/adevtool} vendor/adevtool
      '' + (lib.concatMapStringsSep "\n" (dir: dir.unpackScript) unpackDirs);
    };
  unpackImg = { img, device ? config.device, deviceFamily ? config.deviceFamily, buildID ? cfg.buildID }:
    config.build.mkAndroid {
      name = "unpack-img-${device}-${buildID}";
      unpackPhase = ''
        ${unpackPhase}
      '';
      nativeBuildInputs = with pkgs; [ unzip ];
      buildPhase = ''
        set -e
        cp ${img}/${device}-${lib.toLower buildID}-*.zip img.zip
        cp ${img}/${device}-ota-${lib.toLower buildID}-*.zip ota.zip
        ls -lha vendor/state/

        ${adevtool} generate-all \
          vendor/adevtool/config/${device}.yml \
          -c vendor/state/${device}.json \
          -s img.zip \
          -a ${pkgs.robotnix.build-tools}/aapt2

        ${adevtool} ota-firmware \
          vendor/adevtool/config/${device}.yml \
          -f ota.zip

          cat >>vendor/google_devices/${device}.mk <<-EOH
          # this gets set in the vendored makefiles via adevtool
          # it only gets used if the cts-profile-fix.enable option is set
          ifneq (\$(PRODUCT_OVERRIDE_FINGERPRINT),)
          ADDITIONAL_SYSTEM_PROPERTIES += \
              ro.build.stock_fingerprint=\$(PRODUCT_OVERRIDE_FINGERPRINT)
          endif
          EOH
      '';

      installPhase = ''
        mkdir -p $out
        cp -r vendor/google_devices/${device}/* $out
      '';
    };
in
{
  options.adevtool = {
    enable = mkEnableOption "adevtool";

    buildID = mkOption {
      type = types.str;
      description = "Build ID associated with the upstream img/ota (used to select images)";
      default = config.apv.buildID;
    };

  };
  config = {
    build.adevtool = rec {
      img = fetchImage {
        inherit (config) device;
        inherit (cfg) buildID;
      };
      files = unpackImg {
        inherit (config) device deviceFamily;
        inherit (cfg) buildID;
        inherit img;
      };

      patchPhase = lib.optionalString cfg.enable ''
        export HOME=$(pwd)
        ${lib.concatMapStringsSep "\n"
          (name: ''
            ${pkgs.utillinux}/bin/umount ${config.source.dirs.${name}.relpath}
            rmdir ${config.source.dirs.${name}.relpath}
            cp --reflink=auto --no-preserve=ownership --no-dereference --preserve=links -r ${config.source.dirs.${name}.src} ${config.source.dirs.${name}.relpath}
            chmod u+w -R ${config.source.dirs.${name}.relpath}
          '')
          sepolicyDirNames}

        cp -r ${config.build.adevtool.img}/${config.device}-${lib.toLower cfg.buildID}-*.zip img.zip
        cat <<-EOH | robotnix-build
        ${adevtool} \
          fix-certs \
          -s  img.zip \
          -d ${config.device} \
          -p ${lib.concatStringsSep " " sepolicyDirNames}
        EOH
      '';
    };
    source.dirs = mkIf cfg.enable {
      "vendor/google_devices/${config.device}".src = config.build.adevtool.files;
    };
  };
}
