import re
from xkeysnail.transform import *

define_modmap({
  Key.CAPSLOCK: Key.LEFT_CTRL
})

define_keymap(lambda wm_class: wm_class not in ("St"), {
  K("Super-z"): K("C-z"),
  K("Super-x"): K("C-x"),
  K("Super-c"): K("C-c"),
  K("Super-v"): K("C-v"),
  K("Super-a"): K("C-a"),
  K("Super-f"): K("C-f"),
  K("Super-t"): K("C-t"),
  K("Super-l"): K("C-l"),
  K("Super-w"): K("C-w"),
  K("Super-KEY_1"): K("C-KEY_1"),
  K("Super-KEY_2"): K("C-KEY_2"),
  K("Super-KEY_3"): K("C-KEY_3"),
  K("Super-KEY_4"): K("C-KEY_4"),
  K("Super-KEY_5"): K("C-KEY_5"),
  K("Super-KEY_6"): K("C-KEY_6"),
  K("Super-KEY_7"): K("C-KEY_7"),
  K("Super-KEY_8"): K("C-KEY_8"),
  K("Super-KEY_9"): K("C-KEY_9"),
}, "Global")

define_keymap(re.compile("St"), {
  K("Super-c"): K("M-c"),
  K("Super-v"): K("M-v"),
}, "St copy paste")
