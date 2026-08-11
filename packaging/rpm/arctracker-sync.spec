%global _build_id_links none
# The binary is built beforehand by packaging/build.sh and staged into the
# buildroot, so there is nothing to compile or strip here.
%global debug_package %{nil}
%global __strip /bin/true

Name:           arctracker-sync
Version:        %{version}
Release:        1%{?dist}
Summary:        Sync your ARC Raiders inventory to ARCTracker (unofficial Linux build)

# PolyForm Noncommercial 1.0.0 has no SPDX identifier and is not an OSI licence.
License:        PolyForm-Noncommercial-1.0.0
URL:            https://arctracker.io

Requires:       glibc >= 2.36
Requires:       libxkbcommon
Requires:       libwayland-client
Requires:       libwayland-cursor
Requires:       libwayland-egl
Requires:       libX11
Requires:       libXcursor
Requires:       libXrandr
Requires:       libXi
Requires:       mesa-libGL
Requires:       libcap
Recommends:     xdg-desktop-portal

%description
Keeps an ARCTracker inventory up to date while ARC Raiders runs under Proton.
It watches this machine's own network traffic for the game's connection to the
Embark gateway, decrypts it with the TLS session keys the game writes to
SSLKEYLOGFILE, and posts the resulting sync key to ARCTracker.

Unofficial community build. Upstream (RaidTheory LLC) publishes Windows
releases only; this package is built from source and is not supported by them.

Capture needs CAP_NET_RAW, which is set on the binary at install time; the app
only ever reads traffic on this machine. The TLS key log the game writes can
decrypt every HTTPS session it made while the file existed, account token
included.

%files
# The capability is declared here so rpm records and restores it, rather than
# being applied by a scriptlet that a verify run would then flag as a change.
%caps(cap_net_raw=ep) %attr(0755,root,root) /usr/bin/arctracker-sync
/usr/share/applications/arctracker-sync.desktop
/usr/share/icons/hicolor/256x256/apps/arctracker-sync.png
%license /usr/share/doc/arctracker-sync/LICENSE
%doc /usr/share/doc/arctracker-sync/README.md

%post
if ! getcap /usr/bin/arctracker-sync 2>/dev/null | grep -q cap_net_raw; then
    echo "arctracker-sync: CAP_NET_RAW is not set on the binary." >&2
    echo "  Packet capture will not work — check the filesystem is not nosuid." >&2
fi

%postun
if [ "$1" = 0 ]; then
    echo "arctracker-sync: per-user data was left in place. To remove it:" >&2
    echo "  rm -rf ~/.config/sync ~/.local/share/sync" >&2
fi

%changelog
* Tue Aug 11 2026 ARCTracker Sync Linux packaging - 0.2.0-1
- Initial unofficial Linux package.
