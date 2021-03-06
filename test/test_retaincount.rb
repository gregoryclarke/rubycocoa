require 'test/unit'
require 'osx/cocoa'

system 'make -s' || raise(RuntimeError, "'make' failed")
require './objc_test.bundle'

OSX.ns_import :RetainCount

class RBSubclass < OSX::NSObject
end

class TC_RetainCount < Test::Unit::TestCase

  # retained by Ruby
  def test_rb_rbclass
    assert_equal(1, RBSubclass.alloc.retainCount, 'alloc')
    assert_equal(1, RBSubclass.allocWithZone(nil).retainCount, 'allocWithZone:')
    assert_equal(1, RBSubclass.alloc.init.retainCount, 'alloc.init')
    assert_equal(1, RBSubclass.new.retainCount, 'new')
  end

  # retained by Ruby
  def test_rb_occlass
    assert_equal(1, OSX::NSObject.alloc.retainCount, 'alloc')
    assert_equal(1, OSX::NSObject.alloc.init.retainCount, 'alloc.init')
    assert_equal(1, OSX::NSObject.new.retainCount, 'new')
    # OS X 10.9 or earlier: 1
    # OS X 10.10: NSUIntegerMax
    assert_include([1, OSX::NSUIntegerMax], OSX::NSString.stringWithString('foo').retainCount, 'factory')
  end

  # retained by Objective-C
  def test_objc_rbclass
    assert_equal(1, OSX::RetainCount.rbAllocCount, 'alloc')
    assert_equal(1, OSX::RetainCount.rbInitCount, 'alloc.init') 
    assert_equal(1, OSX::RetainCount.rbNewCount, 'new') 
  end

  # retained by Ruby and Objective-C
  def test_obj_from_objc
    assert_equal(2, OSX::RetainCount.ocObject.retainCount, 'ObjC object')
    assert_equal(2, OSX::RetainCount.rbObject.retainCount, 'Ruby object')
    assert_equal(2, OSX::RetainCount.rbNewObject.retainCount, 'Ruby object(new)')
  end

  # placeholder
  def test_placeholder
    assert_equal(1, OSX::NSMutableString.alloc.init.retainCount,
      'placeholder in ruby') 
    assert_equal(2, OSX::RetainCount.ocObjectFromPlaceholder.retainCount,
      'placeholder in Objc') 
  end

  # CF types
  def test_cf_types
    # /Create/ -> already retained by CF
    url = OSX::CFURLCreateWithString(OSX::KCFAllocatorDefault, "http://www.google.com", nil)
    assert_equal(1, url.retainCount)
    url2 = OSX::CFURLCreateWithString(OSX::KCFAllocatorDefault, "dummy/path", url)
    assert_equal(1, url2.retainCount) # a new object
    assert_equal(2, url.retainCount)  # retained from url2 (+1)
    # /Copy/ -> already retained by CF
    url3 = OSX::CFURLCopyAbsoluteURL(url2)
    assert_equal(1, url3.retainCount) # a new object
    assert_equal(1, url2.retainCount) # not changed
    # Other -> not retained by CF, retained by RubyCocoa
    # TODO: (not implemented)
  end
end

