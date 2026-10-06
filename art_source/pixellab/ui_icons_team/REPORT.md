# UI skin, icons and team art: PixelLab (round AN)

Originals: art_source/legacy/<same path>. Masters here; icon_choice.txt says
which master each icon came from; scripts/ cut the frames and built the
formation. 247 generations.

- UI skin (Theme.csv images, assets/ui/beerhall_*): create_ui_asset kits,
  cut to the old sizes (96x96, bars 32x32) and slice margins. Flat, calm
  middles for readable text. Hover and pressed are made from the button.
- Icons (assets/icons/, 39): create_image_pixen, 64x64, transparent, thick
  outline. Tier files (_1, _2, _3) rise in richness within one family.
- Team (assets/team/): banner_normal_team.png = club crest (create_image_pro,
  128x128); formation_normal_team.png = 4 pixen parts placed at the old 17
  spots, layered in art_source/aseprite/ui_icons_team/; trait_brandteufel.png
  = copy of the new icon.

Open points: class_select.gd crops the crest (KEEP_ASPECT_COVERED); small
icons use linear filtering, so they look soft at 28 px; deep_salts.png is not
used by Items.csv (it names deep_salt).
