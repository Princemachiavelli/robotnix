# SPDX-FileCopyrightText: 2020 Daniel Fullmer and robotnix contributors
# SPDX-License-Identifier: MIT

{ callPackage, lib, substituteAll, fetchFromGitHub, androidPkgs, jdk, gradle }:
let
  androidsdk = androidPkgs.sdk (p: with p; [ cmdline-tools-latest platforms-android-29 build-tools-29-0-2 ]);
  buildGradle = callPackage ./gradle-env.nix {};
in
buildGradle rec {
  name = "Seedvault-${version}.apk";
  version = "11-2.3";

  envSpec = ./gradle-env.json;

  src = (fetchFromGitHub {
    owner = "stevesoltys";
    owner = "seedvault-app";
    repo = "seedvault";
    rev = "11-2.3"; 
    sha256 = "";
  });

  gradleFlags = [ "assembleRelease" ];

  ANDROID_HOME = "${androidsdk}/share/android-sdk";
  nativeBuildInputs = [ jdk ];

  installPhase = ''
    cp app/build/outputs/apk/release/app-release-unsigned.apk $out
  '';
}
