// Copyright (c) 2015, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:analyzer/analyzer.dart' as analyzer;
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/dart/element/type.dart';
import 'package:analyzer/src/dart/ast/ast.dart' show FunctionBodyImpl;
import 'package:analyzer/src/dart/ast/utilities.dart' show NodeReplacer;
import 'package:analyzer/src/dart/element/type.dart' show DynamicTypeImpl;
import 'package:analyzer/src/generated/parser.dart' show ResolutionCopier;
import 'package:analyzer/src/task/strong/info.dart';
import 'package:logging/logging.dart' as logger;

import 'ast_builder.dart';

final _log = new logger.Logger('dev_compiler.reify_coercions');

class NewTypeIdDesc {
  /// If null, then this is not a library level identifier (i.e. it's
  /// a type parameter, or a special type like void, dynamic, etc)
  LibraryElement importedFrom;

  /// True => use/def in same library
  bool fromCurrent;

  /// True => not a source variable
  bool synthetic;
  NewTypeIdDesc({this.fromCurrent, this.importedFrom, this.synthetic});
}

// This class implements a pass which modifies (in place) the ast replacing
// abstract coercion nodes with their dart implementations.
class CoercionReifier extends analyzer.GeneralizingAstVisitor<Object> {
  final cloner = new _TreeCloner();

  /// Makes coercions explicit in the resolved AST, and returns the new AST.
  ///
  /// This should be the entry point for this class.
  /// Entering via the visit functions directly will incorrectly mutate the AST.
  ///
  /// Returns the new compilation units.
  List<CompilationUnit> reify(List<CompilationUnit> units) {
    // Copy the AST before modifying it.
    units = units.map(_clone).toList();
    // Visit the AST and make coercions explicit.
    units.forEach(visitCompilationUnit);
    return units;
  }

  @override
  visitExpression(Expression node) {
    var coercion = CoercionInfo.get(node);
    if (coercion is DownCast) {
      return _visitDownCast(coercion, node);
    }
    return super.visitExpression(node);
  }

  @override
  visitForEachStatement(ForEachStatement node) {
    // Visit other children.
    node.iterable.accept(this);
    node.body.accept(this);

    // If needed, assert a cast inside the body before the variable is read.
    var variable = node.identifier ?? node.loopVariable.identifier;
    var coercion = CoercionInfo.get(variable);
    if (coercion is DownCast) {
      // Build the cast. We will place this cast in the body, so need to clone
      // the variable's AST node and clear out its static type (otherwise we
      // will optimize away the cast).
      var cast = _castExpression(
          _clone(variable)..staticType = DynamicTypeImpl.instance,
          coercion.convertedType);

      var body = node.body;
      var blockBody = <Statement>[RawAstBuilder.expressionStatement(cast)];
      if (body is Block) {
        blockBody.addAll(body.statements);
      } else {
        blockBody.add(body);
      }
      _replaceNode(node, body, RawAstBuilder.block(blockBody));
    }
  }

  void _visitDownCast(DownCast node, Expression expr) {
    expr.visitChildren(this);
    _replaceNode(expr.parent, expr, coerceExpression(expr, node));
  }

  void _replaceNode(AstNode parent, AstNode oldNode, AstNode newNode) {
    if (!identical(oldNode, newNode)) {
      var replaced = parent.accept(new NodeReplacer(oldNode, newNode));
      // It looks like NodeReplacer will always return true.
      // It does throw IllegalArgumentException though, if child is not found.
      assert(replaced);
    }
  }

  /// Coerce [e] using [c], returning a new expression.
  Expression coerceExpression(Expression e, DownCast node) {
    if (e is NamedExpression) {
      Expression inner = coerceExpression(e.expression, node);
      return new NamedExpression(e.name, inner);
    }
    return _castExpression(e, node.convertedType);
  }

  Expression _castExpression(Expression e, DartType toType) {
    // We use an empty name in the AST, because the JS code generator only cares
    // about the target type. It does not look at the AST name.
    var typeName = new TypeName(AstBuilder.identifierFromString(''), null);
    typeName.type = toType;
    var cast = AstBuilder.asExpression(e, typeName);
    cast.staticType = toType;
    return cast;
  }

  /*=T*/ _clone/*<T extends AstNode>*/(/*=T*/ node) {
    var copy = node.accept(cloner);
    ResolutionCopier.copyResolutionData(node, copy);
    return copy;
  }
}

class _TreeCloner extends analyzer.AstCloner {
  void _cloneProperties(AstNode clone, AstNode node) {
    if (clone != null) {
      CoercionInfo.set(clone, CoercionInfo.get(node));
      DynamicInvoke.set(clone, DynamicInvoke.get(node));
    }
  }

  @override
  AstNode cloneNode(AstNode node) {
    var clone = super.cloneNode(node);
    _cloneProperties(clone, node);
    return clone;
  }

  @override
  List cloneNodeList(List list) {
    var clone = super.cloneNodeList(list);
    for (int i = 0, len = list.length; i < len; i++) {
      _cloneProperties(clone[i], list[i]);
    }
    return clone;
  }

  // TODO(jmesserly): ResolutionCopier is not copying this yet.
  @override
  BlockFunctionBody visitBlockFunctionBody(BlockFunctionBody node) {
    var clone = super.visitBlockFunctionBody(node);
    (clone as FunctionBodyImpl).localVariableInfo =
        (node as FunctionBodyImpl).localVariableInfo;
    return clone;
  }

  @override
  ExpressionFunctionBody visitExpressionFunctionBody(
      ExpressionFunctionBody node) {
    var clone = super.visitExpressionFunctionBody(node);
    (clone as FunctionBodyImpl).localVariableInfo =
        (node as FunctionBodyImpl).localVariableInfo;
    return clone;
  }
}
