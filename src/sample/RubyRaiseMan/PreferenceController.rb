#
#  PreferenceController.rb
#  RubyRaiseMan
#
#  Created by FUJIMOTO Hisakuni on Sat Aug 17 2002.
#  Copyright (c) 2001 __MyCompanyName__. All rights reserved.
#

require 'osx/cocoa'

class PreferenceController < OSX::NSWindowController
  include OSX

  BNRTableBgColorKey = "Table Background Color".freeze
  BNREmptyDocKey = "Empty Document Flag".freeze
  BNRColorChanged = "BNRColorChanged".freeze

  ib_outlets :colorWell, :checkbox
  ns_overrides :init, :windowDidLoad

  def init
    initWithWindowNibName "Preferences"
    setWindowFrameAutosaveName "PrefWindow"
    return self
  end

  def windowDidLoad
    reload_user_defaults
  end

  def changeColor (sender)
	color = sender.color
    colorAsData = NSArchiver.archivedDataWithRootObject (color)
    defaults = NSUserDefaults.standardUserDefaults
    defaults.extend RCDictionaryAttachment
    defaults[BNRTableBgColorKey] = colorAsData
	NSNotificationCenter.defaultCenter.
	  postNotificationName_object (BNRColorChanged, color)
  end

  def changeNewEmptyDoc (sender)
    defaults = NSUserDefaults.standardUserDefaults
    defaults.extend RCDictionaryAttachment
    defaults[BNREmptyDocKey] = sender.state
  end

  def resetToDefault (sender)
    defaults = NSUserDefaults.standardUserDefaults
    keys = defaults.dictionaryRepresentation.allKeys
    keys.to_a.each {|key| defaults.removeObjectForKey (key) }
    reload_user_defaults
  end

  private

  def reload_user_defaults
    defaults = NSUserDefaults.standardUserDefaults
    defaults.extend RCDictionaryAttachment
    colorAsData = defaults[BNRTableBgColorKey]
	color = NSUnarchiver.unarchiveObjectWithData (colorAsData)
    @colorWell.setColor (color)
    @checkbox.setState (defaults[BNREmptyDocKey])
	NSNotificationCenter.defaultCenter.
	  postNotificationName_object (BNRColorChanged, color)
  end

end
