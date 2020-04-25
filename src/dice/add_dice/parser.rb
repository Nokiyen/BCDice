# -*- coding: utf-8 -*-
# frozen_string_literal: true

require "utils/ArithmeticEvaluator"
require "utils/normalize"
require "dice/add_dice/node"

class AddDice
  # 加算ロールの構文解析器のクラス
  class Parser
    # 構文解析器を初期化する
    # @param [String] expr 構文解析対象の文字列
    def initialize(expr)
      # 構文解析対象の文字列
      @expr = expr
      # 読み込んだトークンのインデックス
      @idx = 0
      # 構文解析エラーが発生したかどうか
      @error = false
    end

    # 構文解析を実行する
    # @return [Node::Command] 加算ロールコマンド
    def parse()
      lhs, cmp_op, rhs = @expr.partition(/[<>=]+/)

      cmp_op = Normalize.comparison_operator(cmp_op)
      if !rhs.empty? && rhs != "?"
        rhs = ArithmeticEvaluator.new.eval(rhs)
      end

      @tokens = tokenize(lhs)
      lhs = expr()

      if @idx != @tokens.size
        @error = true
      end

      return AddDice::Node::Command.new(lhs, cmp_op, rhs)
    end

    # 構文解析エラーが発生したかどうかを返す
    # @return [Boolean]
    def error?
      @error
    end

    private

    # 構文解析対象の文字列をトークンの配列に変換する
    # @return [Array<String>]
    def tokenize(expr)
      expr.gsub(%r{[\+\-\*/DURS@]}) { |e| " #{e} " }.split(' ')
    end

    # 式
    def expr
      consume("S")

      return add()
    end

    # 加算、減算
    def add
      node = mul()

      loop do
        if consume("+")
          op, rhs = sub_negative_number(:+, mul())
          node = AddDice::Node::BinaryOp.new(node, op, rhs)
        elsif consume("-")
          op, rhs = sub_negative_number(:-, mul())
          node = AddDice::Node::BinaryOp.new(node, op, rhs)
        else
          break
        end
      end

      return node
    end

    # TODO: 処理の説明を書く
    def sub_negative_number(op, rhs)
      if rhs.is_a?(Node::Number) && rhs.literal < 0
        if op == :+
          return [:-, rhs.negate]
        elsif op == :-
          return [:+, rhs.negate]
        end
      end

      [op, rhs]
    end

    # 乗算、除算
    def mul
      node = unary()

      loop do
        if consume("*")
          node = AddDice::Node::BinaryOp.new(node, :*, unary())
        elsif consume("/")
          rhs = unary()
          prefix = take_one_of("U", "R")
          node = Node::Divide.new(node, rhs, prefix)
        else
          break
        end
      end

      return node
    end

    # 単項演算
    def unary
      if consume("+")
        unary()
      elsif consume("-")
        node = unary()

        case node
        when Node::Negate
          node.body
        when Node::Number
          node.negate()
        else
          AddDice::Node::Negate.new(node)
        end
      else
        term()
      end
    end

    # 項：ダイスロール、数値
    def term
      ret = expect_number()
      if consume("D")
        times = ret
        sides = expect_number()
        critical = consume("@") ? expect_number() : nil

        ret = AddDice::Node::DiceRoll.new(times, sides, critical)
      end

      ret
    end

    # トークンを消費する
    #
    # トークンと期待した文字列が合致していた場合、次のトークンに進む。
    # 合致していなかった場合は、進まない。
    #
    # @param [String] str 期待する文字列
    # @return [true] トークンと期待した文字列が合致していた場合
    # @return [false] トークンと期待した文字列が合致していなかった場合
    def consume(str)
      if @tokens[@idx] != str
        return false
      end

      @idx += 1
      return true
    end

    # 複数候補の中から一つトークンを取得する
    #
    # トークンと期待した文字列のいずれかが合致していた場合、次のトークンに進み、合致したトークンを返す
    # 合致していなかった場合は、進まない。
    #
    # @param strs [Array<String>] 期待するトークン文字列
    # @return [String] 合致したトークンの文字列
    # @return [nil] トークンと期待した文字列が合致していなかった場合
    def take_one_of(*strs)
      strs.each do |s|
        if consume(s)
          return s
        end
      end

      return nil
    end

    # 指定された文字列のトークンを要求する
    #
    # トークンと期待した文字列が合致していなかった場合、エラーとする。
    # エラーの有無にかかわらず、次のトークンに進む。
    #
    # @param [String] str 期待する文字列
    # @return [void]
    def expect(str)
      if @tokens[@idx] != str
        @error = true
      end

      @idx += 1
    end

    # 整数のトークンを要求する
    #
    # 整数のトークンならば、対応する整数のノードを返す。
    # そうでなければエラーとし、整数0のノードを返す。
    #
    # エラーの有無にかかわらず、次のトークンに進む。
    #
    # @return [Node::Number] 整数のノード
    def expect_number()
      unless integer?(@tokens[@idx])
        @error = true
        @idx += 1
        return AddDice::Node::Number.new(0)
      end

      ret = @tokens[@idx].to_i
      @idx += 1
      return AddDice::Node::Number.new(ret)
    end

    # 文字列が整数かどうかを返す
    # @param [String] str 対象文字列
    # @return [Boolean]
    def integer?(str)
      # Ruby 1.9 以降では Kernel.#Integer を使うべき
      # Ruby 1.8 にもあるが、基数を指定できない問題がある
      !/^\d+$/.match(str).nil?
    end
  end
end
