// Self-check for the 't'/'T' theme cycle (cycleTheme in public.js).
// Run: node test-cycle-theme.js
var fs = require("fs");
var src = fs.readFileSync(__dirname + "/public.js", "utf8");
var m = src.match(/function cycleTheme\(dir\) \{[\s\S]*?\n  \}/);
if (!m) throw new Error("cycleTheme not found in public.js");
var make = new Function("document", "azBgCycleCustom", m[0] + "\nreturn cycleTheme;");

function run(withCustom) {
  var state = { swatches: [], sel: 0 };
  for (var i = 0; i < 5; i++) {
    (function (i) {
      state.swatches.push({
        classList: {
          contains: function (c) {
            return c === "az-selected" && state.sel === i;
          },
        },
        click: function () {
          state.sel = i;
        },
      });
    })(i);
  }
  // stub of the picker's callback: re-apply photo = deselect all presets
  var custom = withCustom
    ? function () {
        state.sel = -1;
        return true;
      }
    : null;
  var doc = {
    querySelectorAll: function () {
      return state.swatches;
    },
  };
  return { cycle: make(doc, custom), state: state };
}

function trace(withCustom, start, keys) {
  var r = run(withCustom);
  r.state.sel = start;
  var out = [];
  keys.split("").forEach(function (k) {
    r.cycle(k === "t" ? 1 : -1);
    out.push(r.state.sel);
  });
  return out;
}

function eq(actual, expected) {
  var a = JSON.stringify(actual),
    e = JSON.stringify(expected);
  if (a !== e) throw new Error("mismatch: got " + a + ", want " + e);
}

var C = -1; // custom photo active (no preset selected)
// with custom photo: fwd 0->1->2->3->4->photo->0 ; back 0->photo->4->3->2->1->0->photo->4
eq(trace(true, 0, "ttttttTTTTTTT"), [1, 2, 3, 4, C, 0, C, 4, 3, 2, 1, 0, C]);
// full lap each way from the photo stop itself
eq(trace(true, C, "ttttttttt"), [0, 1, 2, 3, 4, C, 0, 1, 2]);
eq(trace(true, C, "TTTTTTTTT"), [4, 3, 2, 1, 0, C, 4, 3, 2]);
// without custom photo: plain wrap both ways
eq(trace(false, 0, "tttttt"), [1, 2, 3, 4, 0, 1]);
eq(trace(false, 0, "TTTTTT"), [4, 3, 2, 1, 0, 4]);
console.log("cycleTheme OK");
