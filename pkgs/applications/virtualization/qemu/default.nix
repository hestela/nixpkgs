{ stdenv, fetchurl, fetchpatch, python2, zlib, pkgconfig, glib
, ncurses, perl, pixman, vde2, alsaLib, texinfo, flex
, bison, lzo, snappy, libaio, gnutls, nettle, curl
, makeWrapper
, attr, libcap, libcap_ng
, CoreServices, Cocoa, rez, setfile
, numaSupport ? stdenv.isLinux && !stdenv.isArm, numactl
, seccompSupport ? stdenv.isLinux, libseccomp
, pulseSupport ? !stdenv.isDarwin, libpulseaudio
, sdlSupport ? !stdenv.isDarwin, SDL
, vncSupport ? true, libjpeg, libpng
, spiceSupport ? !stdenv.isDarwin, spice, spice_protocol
, usbredirSupport ? spiceSupport, usbredir
, xenSupport ? false, xen
, hostCpuOnly ? false
, nixosTestRunner ? false
}:

with stdenv.lib;
let
  version = "2.10.1";
  sha256 = "1a3bjr0ygx4r2qd4nx5jf77jhh4xis3zga27lfryn0b4ap3hn14f";
  audio = optionalString (hasSuffix "linux" stdenv.system) "alsa,"
    + optionalString pulseSupport "pa,"
    + optionalString sdlSupport "sdl,";

  hostCpuTargets = if stdenv.isi686 || stdenv.isx86_64 then "i386-softmmu,x86_64-softmmu"
                      else if stdenv.isArm then "arm-softmmu"
                      else if stdenv.isAarch64 then "aarch64-softmmu"
                      else throw "Don't know how to build a 'hostCpuOnly = true' QEMU";
in

stdenv.mkDerivation rec {
  name = "qemu-"
    + stdenv.lib.optionalString xenSupport "xen-"
    + stdenv.lib.optionalString hostCpuOnly "host-cpu-only-"
    + stdenv.lib.optionalString nixosTestRunner "for-vm-tests-"
    + version;

  src = fetchurl {
    url = "http://wiki.qemu.org/download/qemu-${version}.tar.bz2";
    inherit sha256;
  };

  buildInputs =
    [ python2 zlib pkgconfig glib ncurses perl pixman
      vde2 texinfo flex bison makeWrapper lzo snappy
      gnutls nettle curl
    ]
    ++ optionals stdenv.isDarwin [ CoreServices Cocoa rez setfile ]
    ++ optionals seccompSupport [ libseccomp ]
    ++ optionals numaSupport [ numactl ]
    ++ optionals pulseSupport [ libpulseaudio ]
    ++ optionals sdlSupport [ SDL ]
    ++ optionals vncSupport [ libjpeg libpng ]
    ++ optionals spiceSupport [ spice_protocol spice ]
    ++ optionals usbredirSupport [ usbredir ]
    ++ optionals stdenv.isLinux [ alsaLib libaio libcap_ng libcap attr ]
    ++ optionals xenSupport [ xen ];

  enableParallelBuilding = true;

  patches = [ ./no-etc-install.patch ]
    ++ optional nixosTestRunner ./force-uid0-on-9p.patch
    ++ optional pulseSupport ./fix-hda-recording.patch
    ++ [ (fetchpatch {
           name = "qemu-CVE-2017-15118.patch";
           url = "http://git.qemu.org/?p=qemu.git;a=patch;h=51ae4f8455c9e32c54770c4ebc25bf86a8128183";
           sha256 = "0f9i096dz3h1i8g92y99vak23rjs1shf7prlcxqizsz0fah7wx7h"; })
         (fetchpatch {
           name = "qemu-CVE-2017-17381.patch";
           url = "https://git.kernel.org/pub/scm/virt/kvm/mst/qemu.git/patch/?id=758ead31c7e17bf17a9ef2e0ca1c3e86ab296b43";
           sha256 = "17yw4bqsbywdrbmrikr94yjnfsg853bf4i3k4y3k169387da2yc5"; })
       ];

  hardeningDisable = [ "stackprotector" ];

  preConfigure = ''
    unset CPP # intereferes with dependency calculation
  '';

  configureFlags =
    [ "--smbd=smbd" # use `smbd' from $PATH
      "--audio-drv-list=${audio}"
      "--sysconfdir=/etc"
      "--localstatedir=/var"
    ]
    ++ optional numaSupport "--enable-numa"
    ++ optional seccompSupport "--enable-seccomp"
    ++ optional spiceSupport "--enable-spice"
    ++ optional usbredirSupport "--enable-usb-redir"
    ++ optional hostCpuOnly "--target-list=${hostCpuTargets}"
    ++ optional stdenv.isDarwin "--enable-cocoa"
    ++ optional stdenv.isLinux "--enable-linux-aio"
    ++ optional xenSupport "--enable-xen";

  postFixup =
    ''
      for exe in $out/bin/qemu-system-* ; do
        paxmark m $exe
      done
    '';

  postInstall =
    ''
      # Add a ‘qemu-kvm’ wrapper for compatibility/convenience.
      p="$out/bin/qemu-system-${if stdenv.system == "x86_64-linux" then "x86_64" else "i386"}"
      if [ -e "$p" ]; then
        makeWrapper "$p" $out/bin/qemu-kvm --add-flags "\$([ -e /dev/kvm ] && echo -enable-kvm)"
      fi
    '';

  meta = with stdenv.lib; {
    homepage = http://www.qemu.org/;
    description = "A generic and open source machine emulator and virtualizer";
    license = licenses.gpl2Plus;
    maintainers = with maintainers; [ viric eelco ];
    platforms = platforms.linux ++ platforms.darwin;
  };
}
