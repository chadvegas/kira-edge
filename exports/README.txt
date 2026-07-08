Kira — macOS app icon  (concept: "Zones")
=========================================

WHAT'S HERE
  Kira-1024.png         1024×1024 master — rounded squircle, transparent corners,
                        soft baked margin/shadow-free full-bleed. Use this as the
                        Dock/app icon artwork.
  Kira-1024-square.png  1024×1024 corner-to-corner art (no rounding) — for Xcode's
                        App Icon "Single Size" slot or Icon Composer, which apply
                        the squircle mask, shadow, and (Tahoe) Liquid Glass for you.
  Kira.iconset/         Full Apple size set (16…512 @1x/@2x) with rounded shape +
                        soft drop shadow + margins, for a classic .icns.
  make-icns.command     Builds Kira.icns from the iconset (see note below).


QUICKEST PATH (Xcode 16 / macOS 26 Tahoe)
  Drag Kira-1024-square.png into Icon Composer (or the App Icon "Single Size"
  well). It masks, shadows, and layers it automatically.


CLASSIC .ICNS
  ./make-icns.command          → produces Kira.icns
  (equivalently:  iconutil -c icns Kira.iconset)

  NOTE on the @2x files: Apple requires names like "[email protected]". The export
  filesystem here strips the "@", so those files ship as "icon_16x16-2x.png".
  make-icns.command renames them back to "@2x" before running iconutil. If you
  build by hand, rename every "*-2x.png" → "*@2x.png" first.


COLOR
  Deep-ink ground (#15141E → #0B0A10) with a cool top glow; one accent zone in the
  Kira gradient (#C4CCFF → #7B86FF → #54B8E8).
