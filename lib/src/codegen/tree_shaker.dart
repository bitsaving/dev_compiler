// Copyright (c) 2015, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:io';

import 'package:analyzer/src/generated/ast.dart';
import 'package:analyzer/src/generated/element.dart';
import 'package:analyzer/src/generated/engine.dart' show AnalysisContext;

import '../utils.dart';

typedef bool ReachabilityPredicate(Element e, {bool throwIfNot});
typedef void _Action();

/// Special cases:
/// - Edge to each extension type's method from the implemented interface method (List.add -> JSArray.add)
/// - Root non-tree-shakable elements:
///   - Anything from dart:_runtime
///   - startRootIsolate (dart:_isolate_helper)
///   - registerDevtoolsFormatter (dart:_debugger)
///   - core.String
///   - core.Iterator
///   - core.Object
///   - interceptors.JSNumber
///   - interceptors.JSArray
///   - interceptors.JSBool
///   - JSNumber.floor
///   - JSNumber.truncate
class TreeShakingVisitor extends GeneralizingAstVisitor {
  // final _extensionMembers = <ClassElement, Map<String, ClassMemberElement>>{};
  // final _extensionMappings = <ClassElement, Set<ClassElement>>{};
  // TODO(ochafik): Detect reflect & reflectType.
  bool followReflection;
  bool debug;
  final _pendingActions = <_Action>[];
  final _specialRoots = new Set<Element>.identity();
  final _graph = new DirectedGraph<Object>();
  // final _weakGraph = new DirectedGraph<Object>();
  final AnalysisContext context;

  final _topLevelsByName = <String, Set<Element>>{};
  final _membersByName = <String, Set<ClassMemberElement>>{};
  final _membersByClassByName = <ClassElement, Map<String, ClassMemberElement>>{};

  // final _subclasses = <ClassElement, Set<ClassElement>>{};

  // IOSink _diagnosticOut;
  TreeShakingVisitor(this.context, {this.followReflection : true, this.debug : true}) {
    // _diagnosticOut = stderr;//new File('diagnostic.txt').openWrite();
    // seedRoots();
  }

  _flushPendingActions() {
    _pendingActions.forEach((a) => a());
    _pendingActions.clear();
  }

  _forAllMembers(ClassElement e, action(Element e)) {
    e.methods.forEach(action);
    e.fields.forEach(action);
    e.accessors.forEach(action);
  }

  Map<String, ClassMemberElement> _getClassMembers(ClassElement e) {
    var members = _membersByClassByName.putIfAbsent(e, () {
      var members = <String, ClassMemberElement>{};
      _forAllMembers(e, (m) {
        members[m.name] = _normalize(m);
      });
      return members;
    });
    if (members == null) throw new ArgumentError('$e');
    return members;
  }

  Iterable<Element> _getPotentialTargets(String name, {bool allowTopLevels: true}) {
    return _membersByName[name] ?? const [];
  }
  void _foundTopLevelElement(String name, ExecutableElement e) {
    _topLevelsByName.putIfAbsent(name, () => new Set<Element>.identity()).add(e);
  }

  void _foundMemberElement(String name, ClassMemberElement e) {
    // if (name == 'iterator') stderr.writeln("REGISTERING($name) = ${_str(e)}");
    _membersByName.putIfAbsent(name, () => new Set<ClassMemberElement>.identity()).add(e);
  }

  // registerExtensionTypes(Set<ClassElement> extensionTypes) {
  //   for (var t in extensionTypes) {
  //     _registerExtensionTypes(t);
  //   }
  //   // stderr.writeln('ExtensionMappings:');
  //   // _extensionMembers.forEach((from, tos) {
  //   //   stderr.writeln('\t${from.name}: ${tos.keys.join(", ")}');
  //   // });
  // }

  // _registerInheritance(ClassElement e) {
  //   _registerImplementation(e, _collectHierarchy(e));
  // }
  //
  // void _registerExtensionTypes(ClassElement extensionType, Iterable<ClassElement> ancestors) {
  //   _registerImplementation(extensionType, extensionType.interfaces.map((i) => i.element));
  // }

  // void _registerImplementation(ClassElement implementationType, Iterable<ClassElement> implementedTypes) {
  //   var implementationMembers = _getClassMembers(implementationType);
  //   implementationMembers.forEach((name, e) {
  //     _foundMemberElement(name, e);
  //   });
  //   for (ClassElement interfaceType in implementedTypes) {
  //     var interfaceMembers = _getClassMembers(interfaceType);
  //     interfaceMembers.forEach((name, interfaceMember) {
  //       var extensionMember = implementationMembers[name];
  //       if (extensionMember != null) {
  //         _addEdge(null, interfaceMember, extensionMember);
  //         _addEdge(null, extensionMember, interfaceMember);
  //       }
  //     });
  //   }
  // }

  // buildSpecialLinks() {
  //   var libraries = <String, LibraryElement>{};
  //   LibraryElement lib(String uri) =>
  //       libraries.putIfAbsent(uri, () {
  //         var src = context.sourceFactory.forUri(uri);
  //         return context.computeLibraryElement(src);
  //       });
  //   connect(String libFrom, String typeFrom, String libTo, String typeTo) {
  //     var from = lib(libFrom).getType(typeFrom);
  //     var to = lib(libTo).getType(typeTo);
  //     _graph.addEdge(from, to);
  //   }

  // }

  bool _isSpecialRoot(Element e) {
    e = _normalize(e);
    var uri = e.source.uri.toString();
    var res =
      // e is ClassMemberElement && (
      // e.name == 'values' ||
      // e.name == 'iterator' ||
      // e is MethodElement && e.name == 'moveNext' ||
        // false
      //   e.enclosingElement.name == 'Map' && e.name == 'values'
      // ) ||
      uri.startsWith('dart:_runtime') ||
      uri == 'dart:_debugger' && (debug || e.name == 'registerDevtoolsFormatter') ||
      uri == 'dart:_isolate_helper' && e.name == 'startRootIsolate' ||
      // uri.startsWith('dart:core') && (
      //     e.name == 'List' ||
      //     // e.name == 'Set' ||
      //     e.name == 'String' ||
      //     e.name == 'Iterator' ||
      //     e.name == 'Object'
      // ) ||
      uri.startsWith('dart:_interceptors') && (
        e is ClassMemberElement && (
          e.enclosingElement.name == 'JSNumber' && (
            e.name == 'floor' ||
            e.name == 'truncate' ||
            false
          )
        )
      ) ||
      // e.name == 'iterator' || // TODO: make it weak
      // uri == 'dart:_internal/iterable.dart' && (
      //   e.name == 'MappedIterator' ||
      //   e.name == 'MappedIterable' ||
      //   false
      // ) ||
      // uri.startsWith('dart:collection') && (
      //   e.name == 'ListBase' ||
      //   e.name == 'ListMixin' ||
      //   e.name == 'LinkedHashSetCell' ||
      //   e.name == 'LinkedHashMapCell' ||
      //   e.name == 'IterableBase' ||
      //   e.name == 'LinkedHashMapKeyIterable' ||
      //   e.name == 'LinkedHashMapKeyIterator' ||
      //   e.name == 'ListQueue' ||
      //   // e.name == '_LinkedHashSet' ||
      //   // e.name == '_LinkedHashMap' ||
      //   e is ClassMemberElement && (
      //     // e.enclosingElement.name == 'MappedIterator' ||
      //     // e.enclosingElement.name == 'LinkedHashMapKeyIterable' ||
      //     // e.enclosingElement.name == 'ListQueue' ||
      //     e.enclosingElement.name == '_LinkedHashSet' ||
      //     e.enclosingElement.name == '_LinkedHashMap' ||
      //     // e.enclosingElement.name == 'Map' && e.name == 'values'
      //     false
      //   ) ||
      //   false
      // ) ||
      false;
    return res;
  }

  AstNode getSameOrAncestor(AstNode node, bool predicate(AstNode node)) =>
      predicate(node) ? node : node.getAncestor(predicate);

  Element _currentEnclosingElement;

  _withEnclosingElement(Element e, action()) {
    if (e != null && _isSpecialRoot(e)) _specialRoots.add(_normalize(e));

    var oldEnclosingElement = _currentEnclosingElement;
    _currentEnclosingElement = e ?? oldEnclosingElement;
    var res = action();
    _currentEnclosingElement = oldEnclosingElement;
    return res;
  }

  Element _normalize(Element e) {
    if (e is PropertyAccessorElement) return _normalize(e.variable);
    if (e is ConstructorElement) {
      // Normalize generic constructors (Map<dynamic, dynamic> -> Map<K, V>).
      var cls = e.enclosingElement;
      var ctor = e.isDefaultConstructor
          ? cls.type.lookUpConstructor(e.name, cls.library)
          : cls.getNamedConstructor(e.name);
      return ctor;
    }
    return e;
  }

  _addEdge(AstNode node, Element from, Element to, {bool weak: false}) {
    if (from == null || to == null || from is LibraryElement) {
      var ancestor = node is Declaration ? node : node?.getAncestor((a) => a is Declaration);
      throw new ArgumentError('Invalid edge for $node ($from -> $to). Found ancestor: $ancestor (${ancestor.runtimeType}\n\t<- ${node?.parent}\n\t<- ${node?.parent?.parent}');
    }
    if (from == to) return;

    // if (to.name == 'startRootIsolate') {
    // // if (to is Element && to.name.contains('LinkedHashMap') && from.name.contains('LinkedHashMap')) {
    // stderr.writeln('MAP EDGE(${node.runtimeType}): [${from.name}: ${from.runtimeType}] -> [${to.name}: ${to.runtimeType}]');
    //     '\n$node'
    //   );
    //   try { throw new Error(); } catch (e, s) {
    //     stderr.write(s);
    //   }
    // }
    // _weakGraph.addEdge(from, to);
    // if (!weak) _graph.addEdge(from, to);

    _graph.addEdge(from, to);
  }

  _declareDep(AstNode node, Element to, [Element from, bool weak = false]) {
    // assert(to is Element || to is _UnresolvedElement);

    from ??= _currentEnclosingElement;

    // if (froms.isEmpty) throw new ArgumentError('No origin for destination $to ($node)');

    // if (to is Element) {
      from = _normalize(from);
      to = _normalize(to);
      // if (to.name == '_isStringElement') {
      //   stderr.writeln("FROM: ${from} (${from.runtimeType}) to ${to} (${to.runtimeType})");
      //   stderr.writeln("    ${from.enclosingElement}");
      // }
    // }
    // if (to.name == 'weakPorts') {
    //   stderr.writeln('FROM ${from} -> ${to}');
    //   // stderr.writeln('node.target?.propagatedType?.element = ${node.target?.propagatedType?.element}');
    // }

    _addEdge(node, from, to, weak: weak);
  }

  // static ClassElement _getElement(InterfaceType type) => type.element;

  Iterable<ClassElement> _collectHierarchy(ClassElement e, {bool useExtensions: true}) sync* {
    if (e == null) throw new ArgumentError.notNull("e");
    yield e;
    // if (!e.type.isObject) {
    yield* e.allSupertypes.map((t) => t.element);//.expand((InterfaceType t) => _collectHierarchy(t.element));

      // if (useExtensions) {
      //   yield* _extensionMappings[e] ?? [];
      // }
    // }
  }

  @override
  visitLibraryDirective(LibraryDirective node) {
    // Do nothing.
  }

  @override
  visitPartDirective(PartDirective node) {
    // Do nothing.
  }

  @override
  visitPartOfDirective(PartOfDirective node) {
    // Do nothing.
  }

  @override
  visitImportDirective(ImportDirective node) {
    // Do nothing.
  }

  @override
  visitExportDirective(ExportDirective node) {
    // Do nothing.
  }

  @override
  visitComment(Comment node) {
    // Do nothing.
  }

  @override
  visitTypeName(TypeName node) {
    var e = node?.type?.element;
    if (e != null) _declareDep(node, e);
    super.visitTypeName(node);
  }

  @override
  visitAnnotatedNode(AnnotatedNode node) {
    for (var annotation in node.metadata) {
      _declareDep(node, annotation.elementAnnotation.element);
    }
    super.visitAnnotatedNode(node);
  }

  @override
  visitDeclaredIdentifier(DeclaredIdentifier node) {
    _withEnclosingElement(node.element, () {
      super.visitDeclaredIdentifier(node);
    });
  }

  // @override
  // visitDeclaration(Declaration node) {
  //   if (node is! DeclaredIdentifier &&
  //       node is! MethodDeclaration &&
  //       node is! FunctionDeclaration &&
  //       node is! ClassDeclaration &&
  //       node is! ConstructorDeclaration &&
  //       node is! FieldDeclaration &&
  //       node is! TopLevelVariableDeclaration &&
  //       node is! VariableDeclaration &&
  //       node is! ClassTypeAlias) {
  //     stderr.writeln('DECL: $node (${node.runtimeType})');
  //   }
  //   super.visitDeclaration(node);
  // }

  @override
  visitConstructorDeclaration(ConstructorDeclaration node) {
    _withEnclosingElement(node.element, () {
      var e = node.element?.redirectedConstructor;
      if (e != null) _declareDep(node, e);
      // if (node.element.enclosingElement.name.contains('LinkedHashMap')) {
      //   stderr.writeln('CONSTRUCTOR: $node');
      //   super.visitConstructorDeclaration(node);
      //   stderr.writeln('CONSTRUCTOR DONE');
      //   return;
      // }
      super.visitConstructorDeclaration(node);
    });
  }

  @override
  visitSuperConstructorInvocation(SuperConstructorInvocation node) {
    _declareDep(node, node.staticElement);
    super.visitSuperConstructorInvocation(node);
  }

  @override
  visitConstructorFieldInitializer(ConstructorFieldInitializer node) {
    _declareDep(node, node.fieldName.bestElement);
    super.visitConstructorFieldInitializer(node);
  }

  @override
  visitRedirectingConstructorInvocation(RedirectingConstructorInvocation node) {
    _declareDep(node, node.staticElement);
    super.visitRedirectingConstructorInvocation(node);
  }

  @override
  visitVariableDeclaration(VariableDeclaration node) {
    _withEnclosingElement(node.element, () {
      var e = node.element.type.element;
      if (e != null) _declareDep(node, e);
      super.visitVariableDeclaration(node);
    });
  }

  @override
  visitTopLevelVariableDeclaration(TopLevelVariableDeclaration node) {
    for (var v in node.variables.variables) {
      _foundTopLevelElement(v.name.name, node.element);
    }
    visitVariableDeclarationList(node.variables);
    // super.visitTopLevelVariableDeclaration(node);
  }

  @override
  visitVariableDeclarationList(VariableDeclarationList node) {
    for (VariableDeclaration v in node.variables) {
      _withEnclosingElement(v.element, () {
        if (node.type != null) visitTypeName(node.type);
        visitVariableDeclaration(v);
      });
    }
    // super.visitVariableDeclarationList(node);
  }

  @override
  visitIsExpression(IsExpression node) {
    _declareDep(node, node.type.type.element);
    super.visitIsExpression(node);
  }

  @override
  visitAsExpression(AsExpression node) {
    _declareDep(node, node.type.type.element);
    super.visitAsExpression(node);
  }

  @override
  visitCatchClause(CatchClause node) {
    // TODO(ochafik): Redundant with visitTypeName?
    var e = node.exceptionType?.type?.element;
    if (e != null) _declareDep(node, e);
    super.visitCatchClause(node);
  }

  @override
  visitPropertyAccess(PropertyAccess node) {
    var target = node.realTarget;
    _declareTargetPropertyDep(node, target.bestType.element, node.propertyName.bestElement, node.propertyName.name);
    super.visitPropertyAccess(node);
  }

  @override
  visitExpression(Expression node) {
    var e = node.bestType?.element;
    if (e != null) _declareDep(node, e);
    super.visitExpression(node);
  }

  @override
  visitInstanceCreationExpression(InstanceCreationExpression node) {
    // if (node.bestType?.element?.name?.contains('LinkedHashMap') == true) {
    //   stderr.writeln('INSTANCE CREATION: $node\n\t$_currentEnclosingElement\n\t${node.bestType?.element}\n\t${node.constructorName.staticElement}\n\t${node.staticElement}');
    // }
    // _declareDep(node, node.constructorName.staticElement);
    _declareDep(node, node.staticElement);
    super.visitInstanceCreationExpression(node);
  }

  @override
  visitIndexExpression(IndexExpression node) {
    var op = node.parent is AssignmentExpression ? '[]=' : '[]';
    _declareTargetPropertyDep(node, node.realTarget?.bestType?.element, node.bestElement, op);
    super.visitIndexExpression(node);
  }

  @override
  visitMethodInvocation(MethodInvocation node) {
    // if (node.methodName.name == 'warmup') {
    //   stderr.writeln('${node.target}: ${node.target?.runtimeType}');
    //   // stderr.writeln(node.element.source.uri);
    //   stderr.writeln('node.methodName.bestElement = ${node.methodName.bestElement}');
    //   // stderr.writeln('node.methodName.propagatedElement = ${node.methodName.propagatedElement}');
    //   stderr.writeln('node.target?.bestType?.element = ${node.target?.bestType?.element}');
    // }
    // }
    // stderr.writeln('NODE: ${node}');
    // stderr.writeln('FROM: ${_enclosingElement(node)}');
    // stderr.writeln('node.methodName.bestElement = ${node.methodName.bestElement}');
    // stderr.writeln('node.methodName.propagatedElement = ${node.methodName.propagatedElement}');
    // stderr.writeln('node.target?.propagatedType?.element = ${node.target?.propagatedType?.element}');
    var target = node.realTarget?.bestType?.element;
    // if (target == null && node.target is ThisExpression) {
    //   var enclosingClass = node.getAncestor((a) {
    //     return a is ClassDeclaration || a is ClassTypeAlias;
    //   });
    //   target = enclosingClass.element;
    //   stderr.writeln('$node -> ${target}');
    // }
    _declareTargetPropertyDep(node, target, node.methodName.bestElement, node.methodName.name);
    super.visitMethodInvocation(node);
  }

  void _declareTargetPropertyDep(AstNode node, Element target, Element memberElement, String propertyName) {//Identifier name) {
    if (memberElement != null) {
      _declareDep(node, memberElement);
    }

    if (target is! ClassElement) {
      if (memberElement == null) {
        // TODO(ochafik): lookup top-level functions visible from here? (or not needed?)
        var from = _currentEnclosingElement;
        _pendingActions.add(() {
          var potentialTargets = _getPotentialTargets(propertyName);
          // if (propertyName == 'warmup') stderr.writeln('POTENTIAL($propertyName): ${potentialTargets.map(_str)}');
          for (var potentialTarget in potentialTargets) {
            // stderr.writeln("LAZY DEP ${_str(from)} -> ${_str(potentialTarget)}");
            _declareDep(node, potentialTarget, from, true);
          }
        });
        // _declareDep(node, new _UnresolvedElement(null, propertyName));
      }
    } else {
      // for (var ancestor in _collectHierarchy(target)) {
      //   var members = _getClassMembers(ancestor);
      //   var e = members[propertyName];
      //   if (e != null) _declareDep(node, e);
      // }
    }
  }

  @override
  visitClassDeclaration(ClassDeclaration node) {
    _withEnclosingElement(node.element, () {
      _visitClassElement(node, node.element);
      super.visitClassDeclaration(node);
    });
  }

  void _visitClassElement(AstNode node, ClassElement e) {
    // _registerImplementation(e, _collectHierarchy(e));
    var members = _getClassMembers(e);
    members.forEach((name, e) {
      _foundMemberElement(name, e);
    });
    for (ClassElement ancestor in _collectHierarchy(e)) {
      _getClassMembers(ancestor).forEach((name, ancestorMember) {
        var member = members[name];
        if (member != null) {
          _addEdge(null, ancestorMember, member);
          _addEdge(null, member, ancestorMember);
        }
      });
    }
    // _forAllMembers(e, (m) {
    //   _foundMemberElement(m.name, _normalize(m));
    // });
    for (var ancestor in _collectHierarchy(e)) {
      if (ancestor == e) continue;
      _declareDep(node, ancestor);
    }

    var defaultCtor = e.type.lookUpConstructor('', e.library);
    if (defaultCtor != null) {
      _addEdge(node, e, defaultCtor);
    }
  }

  @override
  visitClassTypeAlias(ClassTypeAlias node) {
    _withEnclosingElement(node.name.bestElement, () {
      _visitClassElement(node, node.element);
      super.visitClassTypeAlias(node);
    });
  }

  @override
  visitFormalParameterList(FormalParameterList node) {
    for (var param in node.parameters) {
      _declareDep(node, param.element);
      if (param is DefaultFormalParameter) param.defaultValue?.accept(this);
      var e = param.element?.type?.element;
      if (e != null) _declareDep(node, e);
    }
    super.visitFormalParameterList(node);
  }

  @override
  visitMethodDeclaration(MethodDeclaration node) {
    //_foundExecutableElement(node.name.name, node.element);
    if (node.isStatic) {
      _declareDep(node, node.element.enclosingElement);
    }
    _withEnclosingElement(node.element, () {
      if (node.returnType != null) visitTypeName(node.returnType);
      if (node.parameters != null) visitFormalParameterList(node.parameters);
      super.visitMethodDeclaration(node);
    });
  }

  @override
  visitFieldDeclaration(FieldDeclaration node) {
    _withEnclosingElement(node.element, () {
      super.visitFieldDeclaration(node);
    });
  }

  @override
  visitFunctionDeclaration(FunctionDeclaration node) {
    _withEnclosingElement(node.element, () {
      if (node.returnType != null) visitTypeName(node.returnType);
      visitFunctionExpression(node.functionExpression);
      super.visitFunctionDeclaration(node);
    });
  }

  @override
  visitFunctionTypeAlias(FunctionTypeAlias node) {
    _withEnclosingElement(node.element, () {
      if (node.returnType != null) visitTypeName(node.returnType);
      visitFormalParameterList(node.parameters);
      super.visitFunctionTypeAlias(node);
    });
  }

  // @override
  // visitPrefixedIdentifier(PrefixedIdentifier node) {
  //   super.visitPrefixedIdentifier(node);
  // }

  @override
  visitIdentifier(Identifier node) {
    var e = node.bestElement ?? node.staticElement;
    if (e != null) {
      _declareDep(node, e);
    } else {
      var enclosingClass = node.getAncestor((a) {
        return a is ClassDeclaration || a is ClassTypeAlias;
      });
      if (enclosingClass != null) {
        _declareTargetPropertyDep(node, enclosingClass.element, e, node.name);
      }
    }
    super.visitIdentifier(node);
  }

  final _diagnosed = new Set<Element>.identity();
  ReachabilityPredicate buildReachabilityPredicate(Set<Element> roots) {
    // stderr.writeln("#\n# BUILDING PREDICATE\n#");
    _flushPendingActions();

    var allRoots = new Set<Element>.identity()..addAll(_specialRoots)..addAll(roots);
    var accessible = _graph.getTransitiveClosure(allRoots);
    // Elements accessible only if their enclosing element is accessible:
    // var weaklyAccessible = _weakGraph.getTransitiveClosure(accessible);
    // for (var e in weaklyAccessible) {
    //   if (e is ClassMemberElement) {
    //     if (accessible.contains(e.enclosingElement)) {
    //       accessible.add(e);
    //     }
    //   }
    // }

    stderr.writeln("ACCESSIBILITY: ${accessible.length} / ${_graph.vertices.length}");

    bool isReachable(Element e, {bool throwIfNot: false}) {
      if (e == null) throw new ArgumentError.notNull('e');
      e = _normalize(e);

      printDiagnostic() {
        if (!_diagnosed.add(e)) return;

        // stderr.writeln("${_str(e)}");//": ${e.runtimeType}");
        // stderr.writeln("SPECIAL ROOTS:\n\t${(_specialRoots.map(_str).toSet().toList()..sort()).join("\n\t")}");
        var path = _graph.getSomePath(allRoots, e);
        if (path != null) {
          stderr.writeln('FOUND PATH to ${_str(e)}:\n\t' + path.map(_str).join('\n\t -> '));
        } else {
          stderr.writeln('FOUND NO PATH ${_str(e)}');
          // path = _weakGraph.getSomePath(allRoots, e);
          // if (path != null) {
          //   stderr.writeln('FOUND WEAK PATH to $e:\n\t' + path.map(_str).join(' -> '));
          // }
          stderr.writeln('\tINCOMING(${_str(e)}): ${_graph.getIncoming(e)?.map(_str)}');
          // stderr.writeln('WEAK INCOMING(${_str(e)}): ${_weakGraph.getIncoming(e)?.map(_str)}');
        }
      }
      // var uri = e.source.uri.toString();
      // if (uri.startsWith('dart:_runtime')) //e.name == 'Baz')// && e.enclosingElement.name == '_LinkedHashSet') //e.name.contains('_ChildNodeListLazy') || e.name.contains('ListBase'))
      // if (e.name == 'run')
      //   printDiagnostic();

      if (accessible.contains(e) || _specialRoots.contains(e)) {
        // if (isInExtensionType() && (e.name == 'floor' || e.name == 'truncate')) stderr.writeln("EXT reachable: ${e.enclosingElement.name}.${e.name}");
        return true;
      }
      // if (e.name == '_Manager') {//uri.startsWith('dart:_runtime') && e.name == 'dynamicR') {
      //   printDiagnostic();
      //   stderr.writeln('SPECIAL TREATMENT: ${_str(e)} (_specialRoots.contains: ${_specialRoots.contains(e)})');
      //   return true;
      // }

      if (throwIfNot) {
        printDiagnostic();
        throw new StateError('Not reachable: ${_str(e)}');
      }
      // stderr.writeln('Unreachable by default: $e: ${e.runtimeType}');
      return false;
    }
    return isReachable;
    // return (e) {
    //   var res = isReachable(e);
    //   if (e.name.contains('_ChildNodeListLazy')) stderr.writeln("REACHABLE(${e.name} = $res");
    //   return res;
    // };
  }

  getTreeShakingData(Element e) =>
      'Incoming: ${(_graph.getIncoming(e) ?? []).map(_str).join(', ')}';
  String _str(Element e) {
    // if (e is PropertyAccessorElement) e = e.variable;
    var suffix = '${e.name} (${e.runtimeType} @ ${e.source?.uri})';
    return e is ClassMemberElement ? '${e.enclosingElement.name}.$suffix' : suffix;
  }
}
