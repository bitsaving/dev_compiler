// Copyright (c) 2015, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:collection' show HashMap, HashSet;
import 'package:analyzer/dart/ast/ast.dart' show Identifier;
import 'package:analyzer/dart/element/element.dart';

import 'js_codegen.dart' show ExtensionTypeSet;
import '../info.dart' show LibraryUnit;

/// We use a storage slot for fields that override or can be overridden by
/// getter/setter pairs.
void findFieldsNeedingStorage(
    HashSet<FieldElement> overrides,
    HashSet<FieldElement> propertyOverrides,
    LibraryUnit library, ExtensionTypeSet extensionTypes) {
  for (var unit in library.partsThenLibrary) {
    for (var cls in unit.element.types) {
      var superclasses = getSuperclasses(cls);
      for (var field in cls.fields) {
        if (!field.isSynthetic && !overrides.contains(field)) {
          checkForPropertyOverride(
              field, superclasses, overrides, extensionTypes);
        }
        if (field.isSynthetic) {
          if (field.setter == null) {
            checkForPropertyOverride(field, superclasses, propertyOverrides, extensionTypes, checkGetter: false);
          } else if (field.getter == null) {
            checkForPropertyOverride(field, superclasses, propertyOverrides, extensionTypes, checkSetter: false);
          }
        }
      }
    }
  }

  return overrides;
}

void checkForPropertyOverride(
    FieldElement field,
    List<ClassElement> superclasses,
    HashSet<FieldElement> overrides,
    ExtensionTypeSet extensionTypes,
    {bool checkGetter: true, bool checkSetter: true}) {
  assert(!field.isSynthetic);

  var library = field.library;

  bool found = false;
  for (var superclass in superclasses) {
    var superprop = getProperty(superclass, library, field.name);
    if (superprop != null) {
      // If we find an abstract getter/setter pair, stop the search.
      var getter = superprop.getter;
      var setter = superprop.setter;
      if (!extensionTypes.isExtensionType(superclass) &&
          (getter == null || getter.isAbstract) &&
          (setter == null || setter.isAbstract)) {
        break;
      }

      // TODO(vsm): Get rid of redundant check here.
      if (checkGetter && getter != null && !getter.isAbstract ||
        checkSetter && setter != null && !setter.isAbstract) {
          found = true;
          // TODO(vsm): Why do we need this?
          // Record that the super property is overridden.
          if (checkGetter && checkSetter && superprop.library == library) overrides.add(superprop);
      }
    }
  }

  // If this we found a super property, then this property overrides it.
  if (found) overrides.add(field);
}

FieldElement getProperty(
    ClassElement cls, LibraryElement fromLibrary, String name) {
  // Properties from a different library are not accessible.
  if (Identifier.isPrivateName(name) && cls.library != fromLibrary) {
    return null;
  }
  for (var accessor in cls.accessors) {
    var prop = accessor.variable;
    if (prop.name == name) return prop;
  }
  return null;
}

List<ClassElement> getSuperclasses(ClassElement cls) {
  var result = <ClassElement>[];
  var visited = new HashSet<ClassElement>();
  while (cls != null && visited.add(cls)) {
    for (var mixinType in cls.mixins.reversed) {
      var mixin = mixinType.element;
      if (mixin != null) result.add(mixin);
    }
    var supertype = cls.supertype;
    if (supertype == null) break;

    cls = supertype.element;
    result.add(cls);
  }
  return result;
}
