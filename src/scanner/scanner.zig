const std = @import("std");
const eql = std.mem.eql;

/// All the possible XML tokens and their metadata.
pub const Token = union(enum) {
    start_tag: []const u8,
    empty_tag: []const u8,
    end_tag: []const u8,
    attribute: AttrData,
    text: []const u8,
    end_of_file,

    pub const AttrData = struct {
        name: []const u8,
        value: []const u8,
    };

    /// Returns the tag name if the token is a start tag.
    pub fn expectStartTag(token: Token) ?[]const u8 {
        switch (token) {
            .start_tag => |name| return name,
            else => return null,
        }
    }

    /// Returns true if the token is a start tag called `name`.
    pub fn expectStartTagName(token: Token, name: []const u8) bool {
        const tag = token.expectStartTag() orelse return false;
        if (!eql(u8, tag, name)) return false;
        return true;
    }
    
    /// Returns the tag name if the token is an empty tag.
    pub fn expectEmptyTag(token: Token) ?[]const u8 {
        switch (token) {
            .empty_tag => |name| return name,
            else => return null,
        }
    }

    /// Returns true if the token is an empty tag called `name`.
    pub fn expectEmptyTagName(token: Token, name: []const u8) bool {
        const tag = token.expectEmptyTag() orelse return false;
        if (!eql(u8, tag, name)) return false;
        return true;
    }

    /// Returns the tag name if the token is an end tag.
    pub fn expectEndTag(token: Token) ?[]const u8 {
        switch (token) {
            .end_tag => |name| return name,
            else => return null,
        }
    }

    /// Returns true if the token is an end tag called `name`.
    pub fn expectEndTagName(token: Token, name: []const u8) bool {
        const tag = token.expectEndTag() orelse return false;
        if (!eql(u8, tag, name)) return false;
        return true;
    }

    /// Returns the attribute data if the token is an attribute.
    pub fn expectAttribute(token: Token) ?AttrData {
        switch (token) {
            .attribute => |data| return data,
            else => return null,
        }
    }

    /// Returns the attribute value if the token is an attribute called `name`.
    pub fn expectAttributeName(token: Token, name: []const u8) ?[]const u8 {
        const attr = token.expectAttribute() orelse return null;
        if (!eql(u8, attr.name, name)) return null;
        return attr.value;
    }

    /// Returns the text if the token is text.
    pub fn expectText(token: Token) ?[]const u8 {
        switch (token) {
            .text => |text| return text,
            else => return null,
        }
    }
};

/// Data structure used to extract XML Tokens from source data. This is done
/// using the `next()` function. If an error is returned, the location of the
/// cursor can be retrieved with `getCurPos()`. This can be used with
/// `printLineDebug(pos)` to print the line showing where the error occurred.
pub const Scanner = struct {
    data: []const u8,
    cursor: usize,
    state: State,

    const State = enum {
        element,
        attribute,
        text
    };

    /// Create a scanner from input data.
    pub fn init(data: []const u8) Scanner {
        return Scanner {
            .data = data,
            .cursor = 0,
            .state = .element,
        };
    }

    /// Gets the next token from the input.
    pub fn next(self: *Scanner) ScannerError!Token {
        switch (self.state) {
            .element => {
                self.skipWhitespace();
                if (self.peek(0) catch { return .end_of_file; } != '<') {
                    self.state = .text;
                    return self.next();
                }
                self.cursor += 1;
                switch (try self.peek(0)) {
                    '!' => {
                        // Skip Comment
                        self.cursor += 1;
                        if (self.indexOf("-->")) |index| {
                            self.cursor += index + 3;
                        } else return ScannerError.OpenComment;
                        return self.next();
                    },
                    '?' => {
                        // Skip Processing Instruction
                        self.cursor += 1;
                        if (self.indexOf("?>")) |index| {
                            self.cursor += index + 2;
                        } else return ScannerError.OpenProcInst;
                        return self.next();
                    },
                    '/' => {
                        self.cursor += 1;
                        const name = try self.readName();
                        self.skipWhitespace();
                        if (try self.peek(0) != '>') {
                            return ScannerError.OpenTag;
                        }
                        self.cursor += 1;
                        return .{ .end_tag = name };
                    },
                    else => {
                        const name = try self.readName();
                        self.skipWhitespace();
                        if (self.indexOf(">")) |i| {
                            if (self.indexOf("<")) |j| {
                                if (j < i) return ScannerError.OpenTag;
                            }
                            self.state = .attribute;
                            if ((i != 0) and (self.remainingData()[i - 1] == '/')) {
                                return .{ .empty_tag = name };
                            } else {
                                return .{ .start_tag = name };
                            }
                        } else return ScannerError.OpenTag;
                    },
                }
            },
            .attribute => {
                switch (try self.peek(0)) {
                    '>' => {
                        self.cursor += 1;
                        self.state = .element;
                        return self.next();
                    },
                    '/' => {
                        self.cursor += 1;
                        if (try self.peek(0) == '>') {
                            self.cursor += 1;
                            self.state = .element;
                            return self.next();
                        } else return ScannerError.UnexpectedChar;
                    },
                    else => {
                        const name = try self.readName();
                        self.skipWhitespace();
                        if (try self.peek(0) != '=') {
                            return ScannerError.UnexpectedChar;
                        }
                        self.cursor += 1;
                        self.skipWhitespace();
                        const value = try self.readValue();
                        self.skipWhitespace();
                        return .{ .attribute = .{
                            .name = name,
                            .value = value,
                        }};
                    },
                }
            },
            .text => {
                const start = self.cursor;
                while (self.peek(0) catch null) |char| {
                    switch (char) {
                        '<', '>' => break,
                        else => self.cursor += 1,
                    }
                }
                self.state = .element;
                return .{ .text = self.data[start..self.cursor] };
            },
        }
    }

    /// Reads the name under the cursor. Advances the cursor to the next
    /// character not part of the name.
    fn readName(self: *Scanner) ![]const u8 {
        const start = self.cursor;
        switch (try self.peek(0)) {
            ':', 'A'...'Z', '_', 'a'...'z' => self.cursor += 1,
            else => return ScannerError.UnexpectedChar,
        }
        while (self.peek(0) catch null) |char| {
            switch (char) {
                ':', 'A'...'Z', '_', 'a'...'z', '-', '.', '0'...'9' => {
                    self.cursor += 1;
                },
                else => break,
            }
        }
        return self.data[start..self.cursor];
    }

    /// Reads the value under the cursor. Advances the cursor to the next
    /// character not part of the value.
    fn readValue(self: *Scanner) ![]const u8 {
        var single = false;
        switch (try self.peek(0)) {
            '\'' => {
                single = true;
                self.cursor += 1;
            },
            '"' => self.cursor += 1,
            else => return ScannerError.UnexpectedChar,
        }
        const start = self.cursor;
        while (self.peek(0) catch null) |char| {
            switch (char) {
                '"' => {
                    self.cursor += 1;
                    if (!single) break;
                },
                '\'' => {
                    self.cursor += 1;
                    if (single) break;
                },
                else => self.cursor += 1,
            }
        }
        return self.data[start..self.cursor - 1];
    }

    /// Gets the index of `needle` relative to cursor position. This only
    /// searches ahead of the cursor.
    fn indexOf(self: *const Scanner, needle: []const u8) ?usize {
        return std.mem.indexOf(u8, self.remainingData(), needle);
    }

    /// Returns a a slice of the data from the cursor to the end.
    fn remainingData(self: *const Scanner) []const u8 {
        if (self.isEnd()) return self.data[self.data.len..];
        return self.data[self.cursor..];
    }

    /// Advances the cursor until the cursor is over a non-whitespace character.
    fn skipWhitespace(self: *Scanner) void {
        while (self.peek(0) catch null) |char| {
            switch (char) {
                ' ', '\t', '\n', '\r' => self.cursor += 1,
                else => return,
            }
        }
    }

    /// Gets the character under the cursor. Does not advance the cursor.
    fn peek(self: *const Scanner, ahead: usize) !u8 {
        if (self.isEnd()) return ScannerError.UnexpectedEOF;
        return self.data[self.cursor + ahead];
    }

    /// Returns true if there is no more data to be read.
    pub fn isEnd(self: *const Scanner) bool {
        return self.cursor >= self.data.len;
    }

    /// Gets the position of the cursor.
    pub fn getCurPos(self: *const Scanner) CurPos {
        return self.indexToPos(self.cursor);
    }

    /// Converts an index into a position.
    pub fn indexToPos(self: *const Scanner, index: usize) CurPos {
        var cur_pos = CurPos {
            .line = 1,
            .col = 1,
        };
        const end = @min(index, self.data.len);
        for (self.data[0..end]) |char| {
            cur_pos.col += 1;
            if (char == '\n') {
                cur_pos.line += 1;
                cur_pos.col = 1;
            }
        }
        return cur_pos;
    }

    /// Returns all the characters on line `num` not including the newline
    /// character at the end.
    pub fn getLine(self: *const Scanner, num: usize) []const u8 {
        if (num == 0) return self.data[0..0];
        var line: usize = 1;
        var start: usize = 0;
        var end: usize = 0;
        for (0..self.data.len) |i| {
            if (self.data[i] == '\n') {
                if (line == num) {
                    end = i;
                    break;
                }
                line += 1;
                start = i + 1;
            }
        }
        if (end == 0) {
            return self.data[start..];
        }
        return self.data[start..end];
    }

    /// Prints the line specified by `pos` with a cursor under the character at
    /// `pos`.
    pub fn printLineDebug(self: *const Scanner, pos: CurPos) void {
        const line = self.getLine(pos.line);
        std.debug.print("  |{d:>4}|{s}\n", .{pos.line, line});
        if (pos.col != 0) {
            const spaces = pos.col + 4 + @max(b10len(pos.line), 4);
            for (1..spaces) |_| {
                std.debug.print(" ", .{});
            }
        }
        std.debug.print("^\n", .{});
    }
};

pub const CurPos = struct {
    line: usize,
    col: usize,
};

pub const ScannerError = error {
    UnexpectedEOF,
    UnexpectedChar,
    OpenTag,
    OpenComment,
    OpenProcInst,
    OpenValue,
};

/// Computes the length of `x` as a string.
fn b10len(x: usize) usize {
    var v = x;
    var len: usize = 0;
    while (v > 0) {
        v /= 10;
        len += 1;
    }
    return len;
}
