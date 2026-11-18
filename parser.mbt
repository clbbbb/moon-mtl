///|
priv enum TokenKind {
  Name(String)
  Number(Int64)
  Mark(String)
  End
}

///|
priv struct Token {
  kind : TokenKind
  position : Int32
}

///|
fn lex(text : String) -> Result[Array[Token], MonitorError] {
  if text.length() > 16384 {
    return Err(ResourceLimit("rule text exceeds 16384 code units"))
  }
  let chars = text.to_array()
  let result : Array[Token] = []
  let mut cursor = 0
  while cursor < chars.length() {
    let at = cursor
    let c = chars[cursor]
    if c == ' ' || c == '\t' || c == '\n' || c == '\r' {
      cursor += 1
      continue
    }
    if (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') || c == '_' {
      let mut name = ""
      while cursor < chars.length() {
        let ch = chars[cursor]
        if !((ch >= 'a' && ch <= 'z') ||
          (ch >= 'A' && ch <= 'Z') ||
          (ch >= '0' && ch <= '9') ||
          ch == '_' ||
          ch == '.') {
          break
        }
        name += ch.to_string()
        cursor += 1
      }
      if !valid_identifier(name) {
        return Err(SyntaxError(at, "identifier exceeds 128 characters"))
      }
      result.push({ kind: Name(name), position: at, })
    } else if c >= '0' && c <= '9' {
      let mut number = 0L
      while cursor < chars.length() &&
            chars[cursor] >= '0' &&
            chars[cursor] <= '9' {
        let digit = (chars[cursor].to_int() - 48).to_int64()
        if number > (9223372036854775807L - digit) / 10L {
          return Err(SyntaxError(at, "integer overflow"))
        }
        number = number * 10L + digit
        cursor += 1
      }
      result.push({ kind: Number(number), position: at, })
    } else {
      let mut mark = c.to_string()
      cursor += 1
      if c == '-' && cursor < chars.length() && chars[cursor] == '>' {
        mark = "->"
        cursor += 1
      } else if c != '!' &&
        c != '&' &&
        c != '|' &&
        c != '(' &&
        c != ')' &&
        c != '[' &&
        c != ']' &&
        c != ',' {
        return Err(SyntaxError(at, "unexpected character " + c.to_string()))
      }
      result.push({ kind: Mark(mark), position: at, })
    }
  }
  result.push({ kind: End, position: chars.length(), })
  Ok(result)
}

///|
priv struct Parser {
  tokens : Array[Token]
  limits : Limits
  mut cursor : Int32
  mut built : Int32
}

///|
fn Parser::mark(self : Parser, expected : String) -> Bool {
  match self.tokens[self.cursor].kind {
    Mark(actual) if actual == expected => {
      self.cursor += 1
      true
    }
    _ => false
  }
}

///|
fn Parser::expect(
  self : Parser,
  expected : String,
) -> Result[Unit, MonitorError] {
  if self.mark(expected) {
    Ok(())
  } else {
    Err(SyntaxError(self.tokens[self.cursor].position, "expected " + expected))
  }
}

///|
fn Parser::number(self : Parser) -> Result[Int64, MonitorError] {
  match self.tokens[self.cursor].kind {
    Number(value) => {
      self.cursor += 1
      Ok(value)
    }
    _ =>
      Err(
        SyntaxError(
          self.tokens[self.cursor].position,
          "expected nonnegative integer",
        ),
      )
  }
}

///|
fn Parser::interval(self : Parser) -> Result[Interval, MonitorError] {
  match self.expect("[") {
    Err(e) => return Err(e)
    Ok(_) => ()
  }
  let lower = match self.number() {
    Err(e) => return Err(e)
    Ok(v) => v
  }
  match self.expect(",") {
    Err(e) => return Err(e)
    Ok(_) => ()
  }
  let upper = match self.number() {
    Err(e) => return Err(e)
    Ok(v) => v
  }
  match self.expect("]") {
    Err(e) => return Err(e)
    Ok(_) => ()
  }
  Interval::new(lower, upper)
}

///|
fn Parser::count(
  self : Parser,
  value : Formula,
) -> Result[Formula, MonitorError] {
  self.built += 1
  if self.built > self.limits.nodes {
    Err(ResourceLimit("parsed formula node budget"))
  } else {
    Ok(value)
  }
}

///|
fn Parser::prefix(
  self : Parser,
  depth : Int32,
) -> Result[Formula, MonitorError] {
  if depth > self.limits.depth {
    return Err(ResourceLimit("parser nesting depth"))
  }
  if self.mark("!") {
    let child = match self.prefix(depth + 1) {
      Err(e) => return Err(e)
      Ok(v) => v
    }
    return self.count(Not(child))
  }
  if self.mark("(") {
    let result = match self.expression(0, depth + 1) {
      Err(e) => return Err(e)
      Ok(v) => v
    }
    match self.expect(")") {
      Err(e) => return Err(e)
      Ok(_) => ()
    }
    return Ok(result)
  }
  let token = self.tokens[self.cursor]
  self.cursor += 1
  match token.kind {
    Name("true") => self.count(Constant(true))
    Name("false") => self.count(Constant(false))
    Name("previous") => {
      let child = match self.prefix(depth + 1) {
        Err(e) => return Err(e)
        Ok(v) => v
      }
      self.count(Previous(child))
    }
    Name("once") | Name("historically") => {
      let window = match self.interval() {
        Err(e) => return Err(e)
        Ok(v) => v
      }
      let child = match self.prefix(depth + 1) {
        Err(e) => return Err(e)
        Ok(v) => v
      }
      if token.kind is Name("once") {
        self.count(Once(window, child))
      } else {
        self.count(Historically(window, child))
      }
    }
    Name("since") =>
      Err(SyntaxError(token.position, "since requires a left operand"))
    Name(name) => self.count(Atom(name))
    _ => Err(SyntaxError(token.position, "expected a formula"))
  }
}

///|
fn Parser::expression(
  self : Parser,
  minimum : Int32,
  depth : Int32,
) -> Result[Formula, MonitorError] {
  let mut left = match self.prefix(depth) {
    Err(e) => return Err(e)
    Ok(v) => v
  }
  while true {
    let (precedence, operation) = match self.tokens[self.cursor].kind {
      Mark("->") => (1, "implies")
      Mark("|") => (2, "or")
      Mark("&") => (3, "and")
      Name("since") => (4, "since")
      _ => (0, "")
    }
    if precedence == 0 || precedence < minimum {
      break
    }
    self.cursor += 1
    let interval = if operation == "since" {
      match self.interval() {
        Err(e) => return Err(e)
        Ok(v) => Some(v)
      }
    } else {
      None
    }
    let next = if operation == "implies" { precedence } else { precedence + 1 }
    let right = match self.expression(next, depth + 1) {
      Err(e) => return Err(e)
      Ok(v) => v
    }
    let combined = match operation {
      "implies" => Implies(left, right)
      "or" => Or(left, right)
      "and" => And(left, right)
      _ => Since(interval.unwrap(), left, right)
    }
    left = match self.count(combined) {
      Err(e) => return Err(e)
      Ok(v) => v
    }
  }
  Ok(left)
}

///|
/// ASCII identifiers; character offsets in errors count Unicode scalar values.
/// Precedence: unary > since > & > | > ->. Implication associates to the right.
pub fn parse(
  text : String,
  limits~ : Limits = Limits::defaults(),
) -> Result[Formula, MonitorError] {
  let tokens = match lex(text) {
    Err(e) => return Err(e)
    Ok(v) => v
  }
  let parser = Parser::{ tokens, limits, cursor: 0, built: 0, }
  let result = match parser.expression(0, 1) {
    Err(e) => return Err(e)
    Ok(v) => v
  }
  if parser.tokens[parser.cursor].kind is End {
    match Plan::new([("parsed", result)], limits~) {
      Err(error) => Err(error)
      Ok(_) => Ok(result)
    }
  } else {
    Err(
      SyntaxError(
        parser.tokens[parser.cursor].position,
        "unexpected trailing token",
      ),
    )
  }
}
