extends RefCounted

# =============================================================
#  THIS FILE IS A LEFTOVER. YOU CAN DELETE IT.
#
#  There used to be TWO copies of this script in the project — this one, and
#  the real one at
#
#      res://src/core/dialogue_choice.gd
#
#  Godot registers a `class_name` exactly once. A second copy anywhere gives
#  you
#
#      Class "DialogueChoice" hides a global script class
#
#  and then refuses to load one of them. That is where your errors came from,
#  and it was my fault: a zip of mine guessed the wrong folder for this file,
#  so instead of overwriting your copy it added a second one beside it.
#
#  ============ WHY THIS FILE IS EMPTY RATHER THAN DELETED ============
#
#  Deleting is the tidy fix, but it is a thing you have to remember to do and
#  it is easy to delete the wrong one of a pair. Emptying it is a copy-and-
#  paste, which is the step that has actually been working. With the
#  `class_name` gone there is no clash, so the error is gone the moment you
#  paste this in.
#
#  ============ WHAT TO DO WITH IT ============
#
#  Nothing, if you like. It does nothing and costs nothing.
#
#  When you want the project tidy: right-click this file in Godot's FileSystem
#  dock and Delete. Use the dock rather than Windows Explorer, so its `.uid`
#  file goes with it. The real script at the path above is untouched.
# =============================================================
