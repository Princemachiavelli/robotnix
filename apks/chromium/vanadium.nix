# SPDX-FileCopyrightText: 2020 Daniel Fullmer and robotnix contributors
# SPDX-License-Identifier: MIT

{ chromium, fetchFromGitHub, git, fetchcipd, linkFarmFromDrvs, fetchurl, lib }:

let
  vanadium_src = fetchFromGitHub {
    owner = "GrapheneOS";
    repo = "Vanadium";
    rev = "114.0.5735.131.0";
    sha256 = "sha256-1HLjaq516f6FKCr+PtRsykRYW5uNJD2zeqQosCAjPUA=";
  };
in
(chromium.override rec {
  name = "vanadium";
  displayName = "Vanadium";
  version = "114.0.5735.131";
  packageName = "app.${name}.browser";
  enableRebranding = false; # Patches already include rebranding
  customGnFlags = {
    is_component_build = false;
    is_debug = false;
    is_official_build = true;
    symbol_level = 1;
    disable_fieldtrial_testing_config = true;

    dfmify_dev_ui = false;

    # enable patented codecs
    ffmpeg_branding = "Chrome";
    proprietary_codecs = true;

    is_cfi = true;
    use_cfi_cast = true;
    # This feature currently doesn't work with with is_cfi=true,
    # see the now deleted recent patch for M109
    # when this flag wasn't added.
    use_relative_vtables_abi = false;

    enable_gvr_services = false;
    enable_remoting = false;
    enable_reporting = false;
  };
  # Needed for patces/0082-update-dependencies.patch in earlier versions of vanadium
  # -- this patch no longer exists at least as of 112.
  depsOverrides = {};
}).overrideAttrs (attrs: {
  # Use git apply below since some of these patches use "git binary diff" format
  postPatch = ''
    ( cd src
      for patchfile in ${vanadium_src}/patches/*.patch; do
        ${git}/bin/git apply --unsafe-paths $patchfile
      done
    )
  '' + attrs.postPatch;
})
