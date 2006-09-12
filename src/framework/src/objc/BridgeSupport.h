/*
 *  BridgeSupport.h
 *  RubyCocoa
 *
 *  Created by Laurent Sansonetti on 8/29/06.
 *  Copyright 2006 Apple Computer. All rights reserved.
 *
 */

/* Ruby and FFI use both autoconf, and some variables collide. */
#if defined(PACKAGE_BUGREPORT)
# undef PACKAGE_BUGREPORT
#endif

#if defined(PACKAGE_NAME) 
# undef PACKAGE_NAME
#endif

#if defined(PACKAGE_STRING)
# undef PACKAGE_STRING
#endif

#if defined(PACKAGE_TARNAME)
# undef PACKAGE_TARNAME
#endif

#if defined(PACKAGE_VERSION)
# undef PACKAGE_VERSION
#endif

#import "ffi.h"

struct bsFunction {
  char *  name;
  int     argc;
  int *   argv;
  int     retval;
  void *  sym;
  BOOL    is_variadic;
  struct {
    ffi_type ** arg_types;
    ffi_type *  ret_type;
  } ffi;
};

struct bsClass {
  char *              name;
  struct st_table *   class_methods;
  struct st_table *   instance_methods;
};

struct bsMethod {
  char *  selector;
  BOOL    is_class_method;
  BOOL    is_predicate;
};

extern struct bsFunction *current_function;

ffi_type *ffi_type_for_octype (int octype);
struct bsMethod *find_bs_method(char *class_name, char *selector, BOOL is_class_method);
void initialize_bridge_support (VALUE mOSX);