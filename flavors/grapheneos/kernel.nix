{ config, lib, pkgs, ... }:

let
  inherit (lib)
    mkIf mkMerge mkDefault;

  postRedfin = lib.elem config.deviceFamily [ "redfin" "barbet" "raviole" "bluejay" "pantah" "tangorpro" "felix" ];
  postRaviole = lib.elem config.deviceFamily [ "raviole" "bluejay" "pantah" "tangorpro" "felix" ];
  clangVersion = if postRaviole then "r450784e" else "r416183b";
  buildScriptFor = {
    "coral" = "build/build.sh";
    "sunfish" = "build/build.sh";
    "redfin" = "build/build.sh";
    "raviole" = "build_slider.sh";
    "bluejay" = "build_bluejay.sh";
    "pantah" = "build_cloudripper.sh";
    "tangorpro" = "build_tangorpro.sh";
    "felix" = "build_felix.sh";
  };
  buildScript = buildScriptFor.${config.deviceFamily};
  realBuildScript ="build/build.sh";
  kernelPrefix = "kernel/android";
  grapheneOSRelease = "${config.adevtool.buildID}.${config.buildNumber}";

  buildConfigVar = "private/msm-google/build.config.${if config.deviceFamily != "redfin" then config.deviceFamily else "redbull"}${lib.optionalString (config.deviceFamily == "redfin") ".vintf"}";
  subPaths = prefix: (lib.filter (name: (lib.hasPrefix prefix name)) (lib.attrNames config.source.dirs));
  kernelSources = subPaths sourceRelpath;
  unpackSrc = name: src: ''
    shopt -s dotglob
    #rm -rf ${name}
    mkdir -p "${name}"
    cp -fr "${src}/." ${name}
  '';
  linkSrc = name: c: lib.optionalString (lib.hasAttr "linkfiles" c) (lib.concatStringsSep "\n" (map
    ({ src, dest }: ''
      mkdir -p $(dirname ${sourceRelpath}/${dest})
      ln -rs ${name}/${src} ${sourceRelpath}/${dest}
    '')
    c.linkfiles));
  copySrc = name: c: lib.optionalString (lib.hasAttr "copyfiles" c) (lib.concatStringsSep "\n" (map
    ({ src, dest }: ''
      mkdir -p $(dirname ${sourceRelpath}/${dest})
      cp -r ${name}/${src} ${sourceRelpath}/${dest}
    '')
    c.copyfiles));
  unpackCmd = name: c: lib.concatStringsSep "\n" [ (unpackSrc name c.src) (linkSrc name c) (copySrc name c) ];
  unpackSrcs = sources: (lib.concatStringsSep "\n"
    (lib.mapAttrsToList unpackCmd (lib.filterAttrs (name: src: (lib.elem name sources)) config.source.dirs)));

  # the kernel build scripts deeply assume clang as of android 13
  stdenv = pkgs.llvmPackages_13.stdenv; 

  repoName = {
    "sargo" = "crosshatch";
    "bonito" = "crosshatch";
    "sunfish" = "coral";
    "bramble" = "redbull";
    "redfin" = "redbull";
    "bluejay" = "bluejay";
    "panther" = "pantah";
    "cheetah" = "pantah";
    "tangorpro" = "tangorpro";
    "felix" = "felix";
  }.${config.device} or config.deviceFamily;
  sourceRelpath = "${kernelPrefix}/${repoName}";

  builtKernelName = {
    "sargo" = "bonito";
    "flame" = "coral";
    "sunfish" = "coral";
    "bluejay" = "bluejay";
    "panther" = "pantah";
    "cheetah" = "pantah";
  }.${config.device} or config.device;
  builtRelpath = "device/google/${builtKernelName}-kernel${lib.optionalString (config.deviceFamily == "redfin" && config.variant != "user") "/vintf"}";

  kernel = config.build.mkAndroid (rec {
    name = "grapheneos-${builtKernelName}-kernel";
    inherit (config.kernel) patches postPatch;

    nativeBuildInputs = with pkgs; [
      perl
      bc
      nettools
      openssl
      rsync
      gmp
      libmpc
      mpfr
      lz4
      which
      nukeReferences
      ripgrep
      glibc.dev.dev.dev
      pkg-config
      autoPatchelfHook
      coreutils
      gawk
    ] ++ lib.optionals postRedfin [
      python
      python3
      bison
      flex
      cpio
      zlib
    ] ++ lib.optionals postRaviole [
      git
      elfutils
    ];

    unpackPhase = ''
      set -eo pipefail
      shopt -s dotglob
      ${unpackSrcs kernelSources}
      chmod -R a+w .
      runHook postUnpack
    '';

    postUnpack = "cd ${sourceRelpath}";

    # Useful to use upstream's build.sh to catch regressions if any dependencies change
    prePatch = ''
      for d in `find . -type d -name '*lib*'`; do
        addAutoPatchelfSearchPath $d
      done
      autoPatchelf prebuilts${lib.optionalString (!postRaviole) "-master"}/clang/host/linux-x86/clang-${clangVersion}/bin
      sed -i '/unset LD_LIBRARY_PATH/d' build/_setup_env.sh
    '';
    preBuild = ''
      mkdir -p ../../../${builtRelpath} out
      chmod a+w -R ../../../${builtRelpath} out
    '';

    # TODO: add KBUILD env vars for pre-redfin on android 13
    buildPhase =
      ''
        set -eo pipefail
        ${preBuild}

        ${if postRaviole
          #then "LTO=full BUILD_AOSP_KERNEL=1 cflags='--sysroot /usr '"
          then "LTO=none BUILD_AOSP_KERNEL=1 cflags='--sysroot /usr '"
          else "BUILD_CONFIG=${buildConfigVar} HOSTCFLAGS='--sysroot /usr '"} \
          LD_LIBRARY_PATH="/usr/lib/:/usr/lib32/" \
          ./${buildScript} \

        ${postBuild}
      '';

    postBuild = ''
      cp -r out/${if postRaviole
                  then "mixed"
                  else
                    if postRedfin
                    then "android-msm-pixel-4.19"
                    else "android-msm-pixel-4.14"}/dist/* ../../../${builtRelpath}
    '';

    installPhase = ''
      cp -r ../../../${builtRelpath} $out
    '';
  });

in
mkIf (config.flavor == "grapheneos" && config.kernel.enable) (mkMerge [
  {
    kernel.name = kernel.name;
    kernel.src = pkgs.writeShellScript "unused" "true";
    kernel.buildDateTime = mkDefault config.source.dirs.${sourceRelpath}.dateTime;
    kernel.relpath = mkDefault builtRelpath;

    build.kernel = kernel;
  }
])
