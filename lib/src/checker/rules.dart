library ddc.src.checker.rules;

import 'package:analyzer/src/generated/ast.dart';
import 'package:analyzer/src/generated/element.dart';
import 'package:analyzer/src/generated/resolver.dart';

import 'package:ddc/src/info.dart';
import 'package:ddc/src/report.dart' show CheckerReporter;

abstract class TypeRules {
  final TypeProvider provider;
  LibraryInfo currentLibraryInfo = null;

  TypeRules(TypeProvider this.provider);

  bool isSubTypeOf(DartType t1, DartType t2);
  bool isAssignable(DartType t1, DartType t2);

  bool isGroundType(DartType t) => true;

  bool isBoolType(DartType t) => t == provider.boolType;
  bool isDoubleType(DartType t) => t == provider.doubleType;
  bool isIntType(DartType t) => t == provider.intType;
  bool isNumType(DartType t) => t.name == "num";

  StaticInfo checkAssignment(Expression expr, DartType t);

  DartType getStaticType(Expression expr) => expr.staticType;

  DartType elementType(Element e);

  /// Returns `true` if the expression is a dynamic property access or prefixed
  /// identifier.
  bool isDynamicGet(Expression expr) {
    var t = getStaticType(expr);
    // TODO(jmesserly): we should not allow all property gets on `Function`
    return t.isDynamic || t.isDartCoreFunction;
  }

  /// Returns `true` if the expression is a dynamic function call or method
  /// invocation.
  bool isDynamicCall(Expression call) {
    var t = getStaticType(call);
    // TODO(jmesserly): fix handling of types with `call` methods. These are not
    // FunctionType, but they also aren't dynamic calls.
    return t.isDynamic || t.isDartCoreFunction || t is! FunctionType;
  }
}

class DartRules extends TypeRules {
  DartRules(TypeProvider provider) : super(provider);

  bool isSubTypeOf(DartType t1, DartType t2) {
    return t1.isSubtypeOf(t2);
  }

  bool isAssignable(DartType t1, DartType t2) {
    return t1.isAssignableTo(t2);
  }

  StaticInfo checkAssignment(Expression expr, DartType toType) {
    final fromType = getStaticType(expr);
    if (!isAssignable(fromType, toType)) {
      return new StaticTypeError(this, expr, toType);
    }
    return null;
  }

  DartType elementType(Element e) {
    return (e as dynamic).type;
  }
}

class RestrictedRules extends TypeRules {
  final CheckerReporter _reporter;

  RestrictedRules(TypeProvider provider, this._reporter) : super(provider);

  DartType getStaticType(Expression expr) {
    var type = expr.staticType;
    if (type != null) return type;
    _reporter.log(new MissingTypeError(expr));
    return provider.dynamicType;
  }

  // TODO(leafp): Revisit this.
  bool isGroundType(DartType t) {
    if (t is FunctionType) return false;
    if (t is TypeParameterType) return false;
    if (t.isDynamic) return true;

    // t must be an InterfacetType.
    var typeArguments = (t as InterfaceType).typeArguments;
    for (var typeArgument in typeArguments) {
      if (!typeArgument.isDynamic) return false;
    }

    return true;
  }

  /// Check that f1 is a subtype of f2. [ignoreReturn] is used in the DDC
  /// checker to determine whether f1 would be a subtype of f2 if the return
  /// type of f1 is set to match f2's return type.
  bool isFunctionSubTypeOf(FunctionType f1, FunctionType f2,
      {bool ignoreReturn: false}) {
    final r1s = f1.normalParameterTypes;
    final o1s = f1.optionalParameterTypes;
    final n1s = f1.namedParameterTypes;
    final r2s = f2.normalParameterTypes;
    final o2s = f2.optionalParameterTypes;
    final n2s = f2.namedParameterTypes;
    final ret1 = ignoreReturn ? f2.returnType : f1.returnType;
    final ret2 = f2.returnType;

    // A -> B <: C -> D if C <: A and
    // either D is void or B <: D
    if (!ret2.isVoid && !isSubTypeOf(ret1, ret2)) return false;

    // Reject if one has named and the other has optional
    if (n1s.length > 0 && o2s.length > 0) return false;
    if (n2s.length > 0 && o1s.length > 0) return false;

    // f2 has named parameters
    if (n2s.length > 0) {
      // Check that every named parameter in f2 has a match in f1
      for (String k2 in n2s.keys) {
        if (!n1s.containsKey(k2)) return false;
        if (!isSubTypeOf(n2s[k2], n1s[k2])) return false;
      }
    }
    // If we get here, we either have no named parameters,
    // or else the named parameters match and we have no optional
    // parameters

    // If f1 has more required parameters, reject
    if (r1s.length > r2s.length) return false;

    // If f2 has more required + optional parameters, reject
    if (r2s.length + o2s.length > r1s.length + o1s.length) return false;

    // The parameter lists must look like the following at this point
    // where rrr is a region of required, and ooo is a region of optionals.
    // f1: rrr ooo ooo ooo
    // f2: rrr rrr ooo
    int rr = r1s.length; // required in both
    int or = r2s.length - r1s.length; // optional in f1, required in f2
    int oo = o2s.length; // optional in both

    for (int i = 0; i < rr; ++i) {
      if (!isSubTypeOf(r2s[i], r1s[i])) return false;
    }
    for (int i = 0, j = rr; i < or; ++i, ++j) {
      if (!isSubTypeOf(r2s[j], o1s[i])) return false;
    }
    for (int i = or, j = 0; i < oo; ++i, ++j) {
      if (!isSubTypeOf(o2s[j], o1s[i])) return false;
    }
    return true;
  }

  bool _isInterfaceSubTypeOf(InterfaceType i1, InterfaceType i2) {
    if (i1 == i2) return true;

    if (i1.element == i2.element) {
      List<DartType> tArgs1 = i1.typeArguments;
      List<DartType> tArgs2 = i2.typeArguments;

      // TODO(leafp): Verify that this is always true
      // Do raw types get filled in?
      assert(tArgs1.length == tArgs2.length);

      for (int i = 0; i < tArgs1.length; i++) {
        DartType t1 = tArgs1[i];
        DartType t2 = tArgs2[i];
        if ((t1 != t2) && !t2.isDynamic) return false;
      }
      return true;
    }

    if (i2.isDartCoreFunction) {
      if (i1.element.getMethod("call") != null) return true;
    }

    if (i1 == provider.objectType) return false;

    if (_isInterfaceSubTypeOf(i1.superclass, i2)) return true;

    for (final parent in i1.interfaces) {
      if (_isInterfaceSubTypeOf(parent, i2)) return true;
    }

    for (final parent in i1.mixins) {
      if (_isInterfaceSubTypeOf(parent, i2)) return true;
    }

    return false;
  }

  bool isSubTypeOf(DartType t1, DartType t2) {
    if (t1 == t2) return true;

    // Null can be assigned to anything else.
    // FIXME: Can this be anything besides null?
    if (t1.isBottom) return true;
    if (t2.isBottom) return false;

    if (t2.isDynamic) return true;
    if (t1.isDynamic) return false;

    // Trivially true for non-primitives.
    if (t2 == provider.objectType) return true;
    if (t1 == provider.objectType) return false;

    // S <: T where S is a type variable
    //  T is not dynamic or object (handled above)
    //  S != T (handled above)
    //  So only true if bound of S is S' and
    //  S' <: T
    if (t1 is TypeParameterType) {
      DartType bound = t1.element.bound;
      if (bound == null) return false;
      return isSubTypeOf(bound, t2);
    }

    if (t2.isDartCoreFunction) {
      if (t1 is FunctionType) return true;
      if (t1.element is ClassElement) {
        if ((t1.element as ClassElement).getMethod("call") != null) return true;
      }
    }

    // "Traditional" name-based subtype check.
    if (t1 is InterfaceType && t2 is InterfaceType) {
      return _isInterfaceSubTypeOf(t1 as InterfaceType, t2 as InterfaceType);
    }

    if (t1 is! FunctionType && t2 is! FunctionType) return false;

    if (t1 is InterfaceType && t2 is FunctionType) {
      // TODO(leafp): check t1 for a call method of the appropriate type
      return false;
    }

    if (t1 is FunctionType && t2 is InterfaceType) {
      // TODO(leafp): check t2 for a call method of the appropriate type
      return false;
    }

    // Functions
    // Note: it appears under the hood all Dart functions map to a class /
    // hidden type that:
    //  (a) subtypes Object (an internal _FunctionImpl in the VM)
    //  (b) implements Function
    //  (c) provides standard Object members (hashCode, toString)
    //  (d) contains private members (corresponding to _FunctionImpl?)
    //  (e) provides a call method to handle the actual function invocation
    //
    // The standard Dart subtyping rules are structural in nature.  I.e.,
    // bivariant on arguments and return type.
    //
    // The below tries for a more traditional subtyping rule:
    // - covariant on return type
    // - contravariant on parameters
    // - 'sensible' (?) rules on optional and/or named params
    // but doesn't properly mix with class subtyping.  I suspect Java 8 lambdas
    // essentially map to dynamic (and rely on invokedynamic) due to similar
    // issues.
    return isFunctionSubTypeOf(t1 as FunctionType, t2 as FunctionType);
  }

  bool isAssignable(DartType t1, DartType t2) {
    return isSubTypeOf(t1, t2);
  }

  // If fromT <: toT, returns the identity coercion.
  // Otherwise, creates a coercion wrapping a function of
  // type fromT as a function of type toT, if:
  //  1) this can be done without changing the reified type
  //  2) The arguments can be coerced (see _coerceTo below)
  //  3) The return value can be coerced or wrapped
  // Otherwise, returns the error coercion
  Coercion _wrapTo(FunctionType fromT, FunctionType toT) {
    final r1s = fromT.normalParameterTypes;
    final o1s = fromT.optionalParameterTypes;
    final n1s = fromT.namedParameterTypes;
    final ret1 = fromT.returnType;

    final r2s = toT.normalParameterTypes;
    final o2s = toT.optionalParameterTypes;
    final n2s = toT.namedParameterTypes;
    final ret2 = toT.returnType;

    Coercion ret = _coerceTo(ret1, ret2, true);

    // Reject if one has named and the other has optional
    if (n1s.length > 0 && o2s.length > 0) return Coercion.error();
    if (n2s.length > 0 && o1s.length > 0) return Coercion.error();

    Map<String, Coercion> ns = new Map<String, Coercion>();
    // toT has named parameters
    if (n2s.length > 0) {
      // Coerce each named parameter from toT to the expected
      // type in fromT (note the contravariance)
      for (String k2 in n2s.keys) {
        if (!n1s.containsKey(k2)) return Coercion.error();
        ns[k2] = _coerceTo(n2s[k2], n1s[k2]);
      }
    }

    // If fromT has more required parameters, reject
    if (r1s.length > r2s.length) return Coercion.error();

    // If toT has more required + optional parameters, reject
    if (r2s.length + o2s.length > r1s.length + o1s.length) {
      return Coercion.error();
    }

    // The parameter lists must look like the following at this point
    // where rrr is a region of required, and ooo is a region of optionals.
    // fromT: rrr ooo ooo ooo
    // toT  : rrr rrr ooo
    int rr = r1s.length; // required in both
    int or = r2s.length - r1s.length; // optional in fromT, required in toT
    int oo = o2s.length; // optional in both

    List<Coercion> rs = new List<Coercion>(r1s.length);
    for (int i = 0; i < rr; ++i) {
      rs[i] = _coerceTo(r2s[i], r1s[i]);
    }
    List<Coercion> os = new List<Coercion>(o1s.length);
    for (int i = 0, j = rr; i < or; ++i, ++j) {
      os[i] = _coerceTo(r2s[j], o1s[i]);
    }
    for (int i = or, j = 0; i < oo; ++i, ++j) {
      os[i] = _coerceTo(o2s[j], o1s[i]);
    }
    for (int i = oo; i < o1s.length; ++i) {
      os[i] = Coercion.identity(o1s[i]);
    }
    return Coercion.wrapper(fromT, rs, os, ns, ret);
  }

  // Produce a coercion which coerces something of type fromT
  // to something of type toT.
  // If wrap is true and both are function types, a closure
  // wrapper coercion is produced using _wrapTo (see above)
  // Returns the error coercion if the types cannot be coerced
  // according to our current criteria.
  Coercion _coerceTo(DartType fromT, DartType toT, [bool wrap = false]) {
    // fromT <: toT, no coercion needed
    if (isSubTypeOf(fromT, toT)) return Coercion.identity(fromT);

    // Downcasting from dynamic to object always succeeds,
    // no coercion needed.
    if (fromT.isDynamic && toT == provider.objectType) {
      return Coercion.identity(fromT);
    }

    // We can use anything as void
    if (toT.isVoid) return Coercion.identity(fromT);

    // For now, we always wrap closures.
    if (wrap && fromT is FunctionType && toT is FunctionType) {
      return _wrapTo(fromT, toT);
    }

    // Downcast if toT <: fromT
    if (isSubTypeOf(toT, fromT)) return Coercion.cast(fromT, toT);

    return Coercion.error();
  }

  StaticInfo checkAssignment(Expression expr, DartType toT) {
    final fromT = getStaticType(expr);
    final Coercion c = _coerceTo(fromT, toT, true);
    if (c is CoercionError) return new StaticTypeError(this, expr, toT);
    if (c is Cast) return new DownCast(this, expr, c);
    if (c is Wrapper) return new ClosureWrap(this, expr, c, toT);
    assert(c is Identity);
    return null;
  }

  DartType elementType(Element e) {
    return (e as dynamic).type;
  }
}