import test from "node:test";
import assert from "node:assert/strict";
import {convertProgram} from "../../src/api.mjs";

const convert = (body) => convertProgram({
  source: `REPORT znative.\nPARAMETERS p_id TYPE i.\nDATA gv TYPE i.\nSTART-OF-SELECTION.\n${body}\n`,
  filename: "znative.prog.abap", mode: "strict", nativePassthrough: true,
});

test("carries a multiline grouped SELECT loop and its body", async () => {
  const result = await convert(`SELECT id COUNT(*) FROM ztab\n  INTO (gv, gv) GROUP BY id.\n  gv = gv + 1.\nENDSELECT.`);
  assert.equal(result.supported, true, JSON.stringify(result.diagnostics));
  assert.match(result.classSource, /SELECT id COUNT\(\*\) FROM ztab\s+INTO \(gv, gv\) GROUP BY id\.[\s\S]*gv = gv \+ 1\.[\s\S]*ENDSELECT\./);
});

test("carries a SELECT loop spanning lines with statements in its body", async () => {
  const result = await convert(`SELECT id FROM ztab
  INTO gv
  WHERE id = p_id.
  gv = gv + 1.
ENDSELECT.`);
  assert.equal(result.supported, true, JSON.stringify(result.diagnostics));
  assert.match(result.classSource, /SELECT id FROM ztab\s+INTO gv\s+WHERE id = mv_p_id\.[\s\S]*gv = gv \+ 1\.[\s\S]*ENDSELECT\./);
});

test("renames only the SQL host operand, preserving columns and literals", async () => {
  const result = await convert(`SELECT p_id FROM ztab\n  WHERE p_id = 1 AND id = p_id AND text = 'p_id.'\n  INTO gv.\n  WRITE 'p_id.'.\nENDSELECT.`);
  assert.equal(result.supported, true, JSON.stringify(result.diagnostics));
  assert.match(result.classSource, /SELECT p_id FROM ztab\s+WHERE p_id = 1 AND id = mv_p_id AND text = 'p_id\.'/);
  assert.match(result.classSource, /write_field\( VALUE #\( text = 'p_id\.'/i);
});

test("does not rewrite a selection name in a comment", async () => {
  const result = await convert(`SELECT id FROM ztab WHERE id = p_id INTO gv. " p_id stays
  WRITE gv.
ENDSELECT.`);
  assert.equal(result.supported, true, JSON.stringify(result.diagnostics));
  assert.match(result.classSource, /WHERE id = mv_p_id INTO gv\.[\s\S]*" p_id stays/);
  assert.doesNotMatch(result.classSource, /" mv_p_id stays/);
});

test("keeps a FORM local that shadows a selection parameter", async () => {
  const result = await convertProgram({source: `REPORT znative.
PARAMETERS p_id TYPE i.
DATA gv TYPE i.
FORM read_rows.
  DATA p_id TYPE i.
  SELECT id FROM ztab WHERE id = p_id INTO gv.
  ENDSELECT.
ENDFORM.
START-OF-SELECTION.
  PERFORM read_rows.`, filename: "znative.prog.abap", mode: "strict", nativePassthrough: true});
  assert.equal(result.supported, true, JSON.stringify(result.diagnostics));
  assert.match(result.classSource, /WHERE id = p_id INTO gv/);
  assert.doesNotMatch(result.classSource, /WHERE id = mv_p_id INTO gv/);
});

test("carries transaction and dataset statements", async () => {
  const result = await convert(`COMMIT WORK.\nROLLBACK WORK.\nOPEN DATASET 'file.txt' FOR INPUT IN TEXT MODE ENCODING DEFAULT.\nREAD DATASET 'file.txt' INTO gv.\nGET DATASET p_id POSITION gv.\nCLOSE DATASET 'file.txt'.`);
  assert.equal(result.supported, true, JSON.stringify(result.diagnostics));
  assert.match(result.classSource, /COMMIT WORK\.[\s\S]*ROLLBACK WORK\.[\s\S]*OPEN DATASET 'file.txt'/);
  assert.match(result.classSource, /GET DATASET mv_p_id POSITION gv/);
});

test("refuses an unclassified statement with its source line", async () => {
  const result = await convert("BOGUS p_id.");
  assert.equal(result.supported, false);
  assert.ok(result.diagnostics.some((item) => item.code === "GGCONV-E201" && item.start.line === 5));
});
