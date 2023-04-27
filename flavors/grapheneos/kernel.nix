{ config, lib, pkgs, ... }:

let
  inherit (lib)
    mkIf mkMerge mkDefault;

  clangVersion = "r450784e";

  postRedfin = lib.elem config.deviceFamily [ "redfin" "barbet" "raviole" "bluejay" "pantah" ];
  postRaviole = lib.elem config.deviceFamily [ "raviole" "bluejay" "pantah" ];
  buildScriptFor = {
    "coral" = "build/build.sh";
    "sunfish" = "build/build.sh";
    "redbull" = "build/build.sh";
    "redfin" = "build/build.sh";
    #"redfin" = "build_redbull.sh";
    "raviole" = "build_slider.sh";
    "bluejay" = "build_bluejay.sh";
    "pantah" = "build_cloudripper.sh";
  };
  buildScript = if (config.androidVersion >= 13) then buildScriptFor.${config.deviceFamily} else "build.sh";
  realBuildScript = if (config.androidVersion >= 13) then "build/build.sh" else "build.sh";
  kernelPrefix = if (config.androidVersion >= 13) then "kernel/android" else "kernel/google";
  grapheneOSRelease = "${config.apv.buildID}.${config.buildNumber}";

  buildConfigFor = {
    #"redfin" = "redbull.vintf";
    "redfin" = "redbull.no-cfi";
    "bluejay" = "bluejay";
  };

  buildConfigVar = "private/msm-google/build.config.${buildConfigFor.${config.deviceFamily}}";
  subPaths = prefix: (lib.filter (name: (lib.hasPrefix prefix name)) (lib.attrNames config.source.dirs));
  kernelSources = subPaths sourceRelpath;
  unpackSrc = name: src: ''
    shopt -s dotglob
    rm -rf ${name}
    mkdir -p $(dirname ${name})
    cp -r ${src} ${name}
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
  llvm = pkgs.llvmPackages_13;
  stdenv = if (config.androidVersion >= 13) then pkgs.stdenv else pkgs.stdenv;

  repoName = {
    "sargo" = "crosshatch";
    "bonito" = "crosshatch";
    "sunfish" = "coral";
    "bramble" = "redbull";
    "redfin" = "redbull";
    "bluejay" = "bluejay";
    "panther" = "pantah";
    "cheetah" = "pantah";
  }.${config.device} or config.deviceFamily;
  sourceRelpath = "${kernelPrefix}/${repoName}";

  builtKernelName = {
    "sargo" = "bonito";
    "flame" = "coral";
    "sunfish" = "coral";
    "bluejay" = "bluejay";
    "panther" = "pantah";
    "cheetah" = "pantah";
    "redbull" = "redbull";
  }.${config.device} or config.device;
  # I think this will miss redbull-kernel/vintf/
  builtRelpath = "device/google/${builtKernelName}-kernel";

  kernel =
    let
      openssl' = pkgs.openssl;
      pkgsCross = pkgs.unstable.pkgsCross.aarch64-android-prebuilt;
      android-stdenv = pkgsCross.gccCrossLibcStdenv;
      android-bintools = android-stdenv.cc.bintools.bintools_bin;
      android-gcc = android-stdenv.cc;
    in
    config.build.mkAndroid (rec {
      name = "grapheneos-${builtKernelName}-kernel";
      inherit (config.kernel) patches postPatch;

      nativeBuildInputs = with pkgs; [
        perl
        bc
        nettools
        openssl'
        openssl'.out
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
        python3
        bison
        flex
        cpio
      ] ++ lib.optionals postRaviole [
        git
        zlib
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
        for d in `find prebuilts -type d -name '*lib*'`; do
          addAutoPatchelfSearchPath $d
        done
        autoPatchelf prebuilts/clang/host/linux-x86/clang-${clangVersion}/bin
        sed -i '/unset LD_LIBRARY_PATH/d' build/_setup_env.sh
      '';
      preBuild = ''
        mkdir -p ../../../${builtRelpath} out
        chmod a+w -R ../../../${builtRelpath} out
      '';

      # TODO: add KBUILD env vars for pre-raviole on android 13
      buildPhase =
        let
          useCodenameArg = config.androidVersion <= 12;
        in
        ''
          set -eo pipefail
          ${preBuild}

          echo "HERE"
          echo $(pwd)
          find . -type f
          ${if postRaviole then "LTO=full BUILD_AOSP_KERNEL=1" else "LTO=thin BUILD_CONFIG=${buildConfigVar}"} \
            cflags="--sysroot /usr " \
            LD_LIBRARY_PATH="/usr/lib/:/usr/lib32/" \
            ./${buildScript} \
            ${lib.optionalString useCodenameArg builtKernelName}

          echo "HERE2"
          find . -type f
          ${postBuild}
        '';

      postBuild = ''
        cp -r out/mixed/dist/* ../../../${builtRelpath}
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
