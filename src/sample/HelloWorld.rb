# HelloWorld.rb
#
# Translate HelloWorld.py of PyObjc (Python Objective-C Bridge) to
# Ruby with RubyCocoa.
#
# A quick guide to runtime name mangling:
#
#      ObjC 		becomes 	  Ruby
#    [ obj method ]   			obj.method
#    [ obj method: arg ]  		obj.method(arg)
#    [ obj method: arg1 withOtherArgs: arg2 ] 
#				obj.method_withOtherArgs( arg1, arg2 )

$stderr.print "just wait..." ; $stderr.flush

require 'osx/cocoa'
include OSX

class AppDelegate <  NSObject

  def applicationDidFinishLaunching(aNotification)
    puts "Hello, World!"
  end

  def sayHello(sender)
    puts "Hello again, World!"
    speak "Hello again, World!"
  end

  def speak(str)
    script = NSAppleScript.alloc.initWithSource("say \"#{str}\"")
    errinfo = OCObject.new
    script.executeAndReturnError(errinfo)
  end

end


if $0 == __FILE__ then
  app = NSApplication.sharedApplication()

  app.setDelegate(AppDelegate.alloc.init)

  frame = [[200.0, 300.0], [250.0, 100.0]]
  win = NSWindow.alloc.initWithContentRect_styleMask_backing_defer(frame, 15, 2, 0)
  win.setTitle 'HelloWorld'
  win.setLevel(3)			# floating window

  hel = NSButton.alloc.initWithFrame [[10.0, 10.0], [80.0, 80.0]]
  win.contentView.addSubview(hel)
  hel.setBezelStyle(4)
  hel.setTitle( 'Hello!' )
  hel.setTarget( app.delegate )
  hel.setAction( "sayHello:" )

#  beep = NSSound.alloc.initWithContentsOfFile_byReference( '/System/Library/Sounds/Tink.Aiff', 1 )
#  hel.setSound( beep )

  bye = NSButton.alloc.initWithFrame [[100.0, 10.0], [80.0, 80.0]]
  win.contentView.addSubview(bye)
  bye.setBezelStyle( 4 )
  bye.setTarget(app)
  bye.setAction('stop:')
  bye.setEnabled( 1 )
  bye.setTitle( 'Goodbye!' )

  adios = NSSound.alloc.initWithContentsOfFile_byReference(  '/System/Library/Sounds/Basso.aiff', 1 )
  bye.setSound( adios )
  
  win.display()
  win.orderFrontRegardless()		## but this one does

  app.run()    
end
