/** -*-objc-*-
 *
 *   $Id$
 *
 *   Copyright (c) 2001 FUJIMOTO Hisakuni <hisa@imasy.or.jp>
 *
 *   This program is free software.
 *   You can distribute/modify this program under the terms of
 *   the GNU Lesser General Public License version 2.
 *
 **/

#import "osx_ocobject.h"
#import <LibRuby/cocoa_ruby.h>
#import <RubyCocoa/ocdata_conv.h> // RubyCocoa.framework
#import <RubyCocoa/RBProxy.h>	// RubyCocoa.framework

#import <Foundation/NSObject.h>
#import <Foundation/NSArchiver.h>
#import <Foundation/NSClassDescription.h>
#import <Foundation/NSConnection.h>
#import <Foundation/NSPortCoder.h>
#import <Foundation/NSScriptClassDescription.h>
#import <Foundation/NSURL.h>
#import <Foundation/NSAutoreleasePool.h>
#import <Foundation/NSString.h>
#import <Foundation/NSMethodSignature.h>
#import <Foundation/NSInvocation.h>
#import <Foundation/NSException.h>

#import <objc/objc-class.h>
#import <string.h>
#import <stdlib.h>

VALUE kOCObject = Qnil;

#define DLOG0(f)          if (ruby_debug == Qtrue) debug_log((f))
#define DLOG1(f,a1)       if (ruby_debug == Qtrue) debug_log((f),(a1))
#define DLOG2(f,a1,a2)    if (ruby_debug == Qtrue) debug_log((f),(a1),(a2))
#define DLOG3(f,a1,a2,a3) if (ruby_debug == Qtrue) debug_log((f),(a1),(a2),(a3))

static void
ocobj_data_free(struct _ocobj_data* dp)
{
  id pool = [[NSAutoreleasePool alloc] init];
  if (dp != nil) {
    if (dp->obj != nil) {
      int i;
      for (i = 0; i < dp->ownership; i++) {
	[dp->obj release];
      }
    }
    free(dp);
  }
  [pool release];
}

static struct _ocobj_data*
ocobj_data_new(id oc_obj)
{
  struct _ocobj_data* dp;
  dp = malloc(sizeof(struct _ocobj_data));
  dp->obj = oc_obj;
  dp->ownership = 0;
  return dp;
}


static VALUE create_rbobj_with_ocid_with_class(id oc_obj, VALUE klass)
{
  VALUE new_obj;
  struct _ocobj_data* dp;

  if (oc_obj == nil) return Qnil;

  dp = ocobj_data_new(oc_obj);

  NS_DURING
    [oc_obj retain];
    dp->ownership += 1;

  NS_HANDLER
    NSString* name = [localException name];
    DLOG2("%@:%@", name, localException);
    if (![name isEqualToString: NSInvalidArgumentException]) {
      [localException raise];
    }

  NS_ENDHANDLER
  
  new_obj = Data_Wrap_Struct(klass, 0, ocobj_data_free, dp);
  return new_obj;
}

VALUE create_rbobj_with_ocid(id oc_obj)
{
  return create_rbobj_with_ocid_with_class(oc_obj, kOCObject);
}

static VALUE ocobj_s_new_with_ocid(int argc, VALUE* argv, VALUE klass)
{
  VALUE obj;
  if (argc < 1) rb_raise(rb_eArgError, "wrong # of arguments");
  obj = create_rbobj_with_ocid_with_class((id)NUM2ULONG(argv[0]), klass);
  argc--; argv++;
  rb_obj_call_init(obj, argc, argv);
  return obj;
}

static Class rbstr_to_nsclass(VALUE rbstr)
{
  id pool = [[NSAutoreleasePool alloc] init];
  Class result;
  rbstr = rb_obj_as_string(rbstr);
  result = NSClassFromString([NSString stringWithCString: STR2CSTR(rbstr)]);
  [pool release];
  return result;
}

static Class find_class_of(VALUE klass)
{
  Class result = nil;
  id pool = [[NSAutoreleasePool alloc] init];
  const char* classname = rb_class2name(klass);
  result = NSClassFromString([NSString stringWithCString: classname]);
  [pool release];
  return result;
} 

static VALUE new_with_occlass(VALUE klass, Class nsclass)
{
  VALUE obj;
  id nsobj;

  if (nsclass == nil)
    rb_raise(rb_eArgError, "class '%s' is nothing.",  
	     STR2CSTR(rb_obj_as_string(klass)));

  nsobj = [nsclass alloc];	// retainCount +1
  obj = create_rbobj_with_ocid_with_class(nsobj, klass); // retainCount +1
  [nsobj release]; // retainCount -1
  OCOBJ_DATA_PTR(obj)->ownership -= 1; // remove one ownership

  //  if ([nsobj isKindOfClass: [RBProxy class]]) {
  if (nsobj->isa == [RBProxy class]) {
    nsobj = [nsobj initWithRubyObject: obj];
  }
  else {
    nsobj = [nsobj init];
  }

  return obj;
}

static VALUE ocobj_s_new_with_classname(int argc, VALUE* argv, VALUE klass)
{
  VALUE obj;
  Class nsclass;
  id nsobj;
  if (argc < 1) rb_raise(rb_eArgError, "wrong # of arguments");
  nsclass = rbstr_to_nsclass(argv[0]);
  obj = new_with_occlass(klass, nsclass);
  argc--; argv++;
  rb_obj_call_init(obj, argc, argv);
  return obj;
}

static VALUE ocobj_s_new(int argc, VALUE* argv, VALUE klass)
{
  VALUE obj;

  obj = new_with_occlass(klass, [RBProxy class]);
  rb_obj_call_init(obj, argc, argv);
  return obj;
}

static BOOL
ocm_perform(int argc, VALUE* argv, VALUE rcv, VALUE* result)
{
  id oc_rcv = OCOBJ_ID_OF(rcv);
  SEL oc_sel;
  const char* ret_type;
  int num_of_args;
  id args[2];
  id pool;
  id oc_result;
  id oc_msig;
  int i;

  if ((argc < 1) || (argc > 3)) return NO;

  oc_sel = rbobj_to_nssel(argv[0]);
  argc--;
  argv++;

  oc_msig = [oc_rcv methodSignatureForSelector: oc_sel];
  if (oc_msig == nil) return NO;

  ret_type = [oc_msig methodReturnType];
  if (*ret_type != _C_ID && *ret_type != _C_CLASS) return NO;

  num_of_args = [oc_msig numberOfArguments] - 2;
  if (num_of_args > 2) return NO;

  pool = [[NSAutoreleasePool alloc] init];
  DLOG2("ocm_perfom (%@): ret_type=%s", NSStringFromSelector(oc_sel), ret_type);

  for (i = 0; i < num_of_args; i++) {
    const char* arg_type = [oc_msig getArgumentTypeAtIndex: (i+2)];
    DLOG2("    arg_type[%d]: %s", i, arg_type);
    if (*arg_type != _C_ID && *arg_type != _C_CLASS) return NO;
    args[i] = nil;
    if (i < argc) {
      if (!rbobj_to_nsobj(argv[i], &(args[i]))) {
	[pool release];
	return NO;
      }
    }
  }

  DLOG0("    NSObject#performSelector ...");
  switch (num_of_args) {
  case 0:
    oc_result = [oc_rcv performSelector: oc_sel];
    break;
  case 1:
    oc_result = [oc_rcv performSelector: oc_sel withObject: args[0]];
    break;
  case 2:
    oc_result = [oc_rcv performSelector: oc_sel withObject: args[0]
			withObject: args[1]];
    break;
  default:
    oc_result = nil;
  }
  DLOG0("    NSObject#performSelector: done.");

  if (oc_result == oc_rcv)
    *result = rcv;
  else
    *result = create_rbobj_with_ocid(oc_result);

  [pool release];
  return YES;
}

static BOOL
ocm_invoke(int argc, VALUE* argv, VALUE rcv, VALUE* result)
{
  id oc_rcv = OCOBJ_ID_OF(rcv);
  SEL oc_sel;
  const char* ret_type;
  int num_of_args;
  id pool;
  id oc_result;
  id oc_msig;
  id oc_inv;
  int i;

  if (argc < 1) return NO;

  oc_sel = rbobj_to_nssel(argv[0]);
  argc--;
  argv++;

  oc_msig = [oc_rcv methodSignatureForSelector: oc_sel];
  if (oc_msig == nil) return NO;

  ret_type = [oc_msig methodReturnType];
  num_of_args = [oc_msig numberOfArguments] - 2;

  pool = [[NSAutoreleasePool alloc] init];
  DLOG2("ocm_invoke (%@): ret_type=%s", NSStringFromSelector(oc_sel), ret_type);

  oc_inv = [NSInvocation invocationWithMethodSignature: oc_msig];
  [oc_inv setTarget: oc_rcv];
  [oc_inv setSelector: oc_sel];

  // set arguments
  for (i = 0; i < num_of_args; i++) {
    VALUE arg = (i < argc) ? argv[i] : Qnil;
    const char* octype_str = [oc_msig getArgumentTypeAtIndex: (i+2)];
    int octype = to_octype(octype_str);
    void* ocdata;
    BOOL f_conv_success;
    DLOG2("    arg_type[%d]: %s", i, octype_str);
    ocdata = ocdata_malloc(octype);
    f_conv_success = rbobj_to_ocdata(arg, octype, ocdata);
    if (f_conv_success) {
      [oc_inv setArgument: ocdata atIndex: (i+2)];
      free(ocdata);
    }
    else {
      free(ocdata);
      [pool release];
      rb_raise(rb_eRuntimeError,
	       "cannot convert the argument #%d as '%s' to NS argument.",
	       i, octype_str);
      return NO;
    }
  }

  DLOG0("    NSInvocation#invoke ...");
  [oc_inv invoke];
  DLOG0("    NSInvocation#invoke: done.");

  // get result
  if ([oc_msig methodReturnLength] > 0) {
    int octype = to_octype([oc_msig methodReturnType]);
    if ((octype == _C_ID) || (octype == _C_CLASS)) {
      id rcv_id, data_id;
      [oc_inv getReturnValue: &data_id];
      rcv_id = OCOBJ_ID_OF(rcv);
      if (rcv_id == data_id)
	*result = rcv;
      else
	*result = create_rbobj_with_ocid(data_id);
    }
    else {
      BOOL f_conv_success;
      void* result_data = ocdata_malloc(octype);
      [oc_inv getReturnValue: result_data];
      f_conv_success = ocdata_to_rbobj(octype, result_data, result);
      free(result_data);
      if (!f_conv_success) {
	[pool release];
	rb_raise(rb_eRuntimeError,
		 "cannot convert the result as '%s' to Ruby Object.", ret_type);
	return NO;
      }
    }
  }
  else {
    *result = nil;
  }

  [pool release];
  return YES;
}


static Ivar
ivar_for(id ocrcv, SEL a_sel)
{
  id pool = [[NSAutoreleasePool alloc] init];
  id nsname = NSStringFromSelector(a_sel);
  Ivar iv = class_getInstanceVariable([ocrcv class], [nsname cString]);
  [pool release];
  return iv;
}

static BOOL
ocm_ivar(VALUE rcv, VALUE name, VALUE* result)
{
  BOOL f_ok = NO;
  id ocrcv = OCOBJ_ID_OF(rcv);
  id pool = [[NSAutoreleasePool alloc] init];
  id nsname = rbobj_to_nsselstr(name);
  Ivar iv = class_getInstanceVariable([ocrcv class], [nsname cString]);
  DLOG1("ocm_ivar (%@)", nsname);
  if (iv) {
    int octype = to_octype(iv->ivar_type);
    DLOG2("    ocm_ivar (%@) ret_type: %s", nsname, iv->ivar_type);
    if (octype_object_p(octype)) {
      void* val;
      iv = object_getInstanceVariable(ocrcv, [nsname cString], &val);
      *result = create_rbobj_with_ocid((id)val);
      f_ok = YES;
    }
    else {
      void* val;
      iv = object_getInstanceVariable(ocrcv, [nsname cString], &val);
      f_ok = ocdata_to_rbobj(octype, val, result);
    }
  }
  [pool release];
  return f_ok;
}

static BOOL
ocm_send(int argc, VALUE* argv, VALUE rcv, VALUE* result)
{
  BOOL ret = NO;
  if (argc < 1) return NO;

  DLOG0("ocm_send ...");
  if (ocm_perform(argc, argv, rcv, result)) ret = YES;
  else if (ocm_invoke(argc, argv, rcv, result)) ret = YES;
  else if (ocm_ivar(rcv, argv[0], result)) ret = YES;
  DLOG0("ocm_send done");

  return ret;
}

/*************************************************/

static VALUE
ocobj_ocid(VALUE rcv)
{
  unsigned long oid = (unsigned long) OCOBJ_ID_OF(rcv);
  return UINT2NUM(oid);
}

static VALUE
ocobj_inc_ownership(VALUE rcv)
{
  OCOBJ_DATA_PTR(rcv)->ownership += 1;
  return INT2NUM(OCOBJ_DATA_PTR(rcv)->ownership);
}

static VALUE
ocobj_dec_ownership(VALUE rcv)
{
  OCOBJ_DATA_PTR(rcv)->ownership -= 1;
  return INT2NUM(OCOBJ_DATA_PTR(rcv)->ownership);
}

static VALUE
ocobj_ownership_cnt(VALUE rcv)
{
  return INT2NUM(OCOBJ_DATA_PTR(rcv)->ownership);
}

static VALUE
ocobj_inspect(VALUE rcv)
{
  VALUE result;
  char s[256];
  id oc_rcv = OCOBJ_ID_OF(rcv);
  id pool = [[NSAutoreleasePool alloc] init];
  const char* class_desc = [[[oc_rcv class] description] cString];
  const char* desc = [[oc_rcv description] cString];
  snprintf(s, sizeof(s), "#<OCObject:0x%x class='%s' id=%X>",
	   NUM2ULONG(rb_obj_id(rcv)), class_desc, oc_rcv);
  result = rb_str_new2(s);
  [pool release];
  return result;
}

static VALUE
ocobj_ocm_responds_p(VALUE rcv, VALUE sel)
{
  VALUE result = Qfalse;
  id oc_rcv = OCOBJ_ID_OF(rcv);
  SEL oc_sel = rbobj_to_nssel(sel);
  if ([oc_rcv respondsToSelector: oc_sel] == NO) {
    if (ivar_for(oc_rcv, oc_sel) != nil)
      result = YES;
  }
  return result;
}

static VALUE
ocobj_ocm_perform(int argc, VALUE* argv, VALUE rcv)
{
  VALUE result;
  id pool = [[NSAutoreleasePool alloc] init];
  if (!ocm_perform(argc, argv, rcv, &result)) {
    [pool release];
    if (argc > 0) {
      VALUE asstr = rb_obj_as_string(argv[0]);
      rb_raise(rb_eRuntimeError, "ocm_perform failed: %s", STR2CSTR(asstr));
    }
    else {
      rb_raise(rb_eRuntimeError, "ocm_perform failed");
    }
  }
  [pool release];
  return result;
}

static VALUE
ocobj_ocm_invoke(int argc, VALUE* argv, VALUE rcv)
{
  VALUE result;
  id pool = [[NSAutoreleasePool alloc] init];
  if (!ocm_invoke(argc, argv, rcv, &result)) {
    [pool release];
    if (argc > 0) {
      VALUE asstr = rb_obj_as_string(argv[0]);
      rb_raise(rb_eRuntimeError, "ocm_invoke failed: %s", STR2CSTR(asstr));
    }
    else {
      rb_raise(rb_eRuntimeError, "ocm_invoke failed");
    }
  }
  [pool release];
  return result;
}

static VALUE
ocobj_ocm_ivar(VALUE rcv, VALUE name)
{
  VALUE result;
  id pool = [[NSAutoreleasePool alloc] init];
  if (!ocm_ivar(rcv, name, &result)) {
    [pool release];
    rb_raise(rb_eRuntimeError, "ocm_ivar failed");
  }
  [pool release];
  return result;
}

static VALUE
ocobj_ocm_send(int argc, VALUE* argv, VALUE rcv)
{
  VALUE result;
  id pool = [[NSAutoreleasePool alloc] init];
  if (!ocm_send(argc, argv, rcv, &result)) {
    [pool release];
    if (argc > 0) {
      VALUE asstr = rb_obj_as_string(argv[0]);
      rb_raise(rb_eRuntimeError, "ocm_send failed: %s", STR2CSTR(asstr));
    }
    else {
      rb_raise(rb_eRuntimeError, "ocm_send failed");
    }
  }
  [pool release];
  return result;
}

/*****************************************/

VALUE
init_class_OCObject(VALUE outer)
{
  kOCObject = rb_define_class_under(outer, "OCObject", rb_cObject);

  rb_define_singleton_method(kOCObject, "new_with_ocid", ocobj_s_new_with_ocid, -1);
  rb_define_singleton_method(kOCObject, "new_with_classname", ocobj_s_new_with_classname, -1);
  rb_define_singleton_method(kOCObject, "new", ocobj_s_new, -1);

  rb_define_method(kOCObject, "__ocid__", ocobj_ocid, 0);
  rb_define_method(kOCObject, "__inspect__", ocobj_inspect, 0);
  rb_define_method(kOCObject, "__inc_ownership__", ocobj_inc_ownership, 0);
  rb_define_method(kOCObject, "__dec_ownership__", ocobj_dec_ownership, 0);
  rb_define_method(kOCObject, "__ownership_cnt__", ocobj_ownership_cnt, 0);

  rb_define_method(kOCObject, "inspect", ocobj_inspect, 0);

  rb_define_method(kOCObject, "ocm_responds?", ocobj_ocm_responds_p, 1);
  rb_define_method(kOCObject, "ocm_perform", ocobj_ocm_perform, -1);
  rb_define_method(kOCObject, "ocm_invoke", ocobj_ocm_invoke, -1);
  rb_define_method(kOCObject, "ocm_ivar", ocobj_ocm_ivar, 1);
  rb_define_method(kOCObject, "ocm_send", ocobj_ocm_send, -1);

  return kOCObject;
}
