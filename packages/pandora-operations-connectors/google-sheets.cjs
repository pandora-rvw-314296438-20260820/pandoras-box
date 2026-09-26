"use strict";
const { demand, digest, frozen, integer } = require("../pandora-operations-room/contracts");
const { inputDigest, ingestRows, planSheetWriteback } = require("../pandora-operations-room/sheet-adapter");
const { NativeJsonClient, failure } = require("./http.cjs");
function cellValue(cell) {
  const value = cell?.userEnteredValue || {};
  demand(!Object.hasOwn(value, "formulaValue"), "SHEET_FORMULA_INPUT_DENIED");
  if (Object.hasOwn(value, "stringValue")) return value.stringValue;
  if (Object.hasOwn(value, "numberValue")) return value.numberValue;
  if (Object.hasOwn(value, "boolValue")) return value.boolValue;
  return "";
}
function writableCell(cell, value) {
  demand(!cell?.userEnteredValue?.formulaValue && !cell?.chipRuns?.length &&
    !cell?.textFormatRuns?.length, "SHEET_STRUCTURED_OUTPUT_DENIED");
  const rule = cell?.dataValidation;
  if (!rule) return;
  const options = rule.condition?.values?.map((x) => x.userEnteredValue) || [];
  demand(rule.condition?.type === "ONE_OF_LIST" && options.includes(value),
    "SHEET_OUTPUT_VALIDATION_DENIED");
}
class GoogleSheetsConnector {
  #binding;
  #http;
  constructor({ binding, getAccessToken, fetchImpl, timeoutMs }) {
    demand(binding && /^[A-Za-z0-9_-]{10,200}$/.test(binding.spreadsheetId),
      "SHEET_BINDING_INVALID");
    integer(binding.sheetId, 0, 2147483647, "SHEET_ID_INVALID");
    integer(binding.headerRow, 1, 10000, "SHEET_HEADER_INVALID");
    integer(binding.maxRows, 1, 500, "SHEET_ROW_BOUND_INVALID");
    integer(binding.maxColumns, 14, 48, "SHEET_COLUMN_BOUND_INVALID");
    this.#binding = frozen({ spreadsheetId: binding.spreadsheetId, sheetId: binding.sheetId,
      headerRow: binding.headerRow, maxRows: binding.maxRows, maxColumns: binding.maxColumns });
    this.#http = new NativeJsonClient({ origin: "https://sheets.googleapis.com",
      getToken: getAccessToken, fetchImpl, timeoutMs });
  }
  async read({ signal } = {}) {
    const b = this.#binding;
    const fields = "spreadsheetId,sheets(properties(sheetId,title,gridProperties),data(startRow,startColumn,rowData(values(userEnteredValue,dataValidation,chipRuns,textFormatRuns))))";
    const response = await this.#http.request(
      `/v4/spreadsheets/${b.spreadsheetId}:getByDataFilter?fields=${encodeURIComponent(fields)}`, {
        method: "POST", mutation: false, signal,
        body: { includeGridData: true, dataFilters: [{ gridRange: { sheetId: b.sheetId,
          startRowIndex: b.headerRow - 1, endRowIndex: b.headerRow + b.maxRows,
          startColumnIndex: 0, endColumnIndex: b.maxColumns } }] },
      });
    demand(response.data?.spreadsheetId === b.spreadsheetId &&
      response.data.sheets?.length === 1, "SHEET_READBACK_TARGET_MISMATCH");
    const sheet = response.data.sheets[0];
    demand(sheet.properties?.sheetId === b.sheetId && sheet.data?.length === 1,
      "SHEET_READBACK_TARGET_MISMATCH");
    const data = sheet.data[0];
    demand((data.startRow ?? 0) === b.headerRow - 1 && (data.startColumn ?? 0) === 0,
      "SHEET_READBACK_RANGE_MISMATCH");
    const cells = data.rowData?.map((r) => r.values || []) || [];
    demand(cells.length >= 1 && cells.length <= b.maxRows + 1 &&
      cells.every((r) => r.length <= b.maxColumns), "SHEET_READBACK_RANGE_MISMATCH");
    const headers = cells[0].map(cellValue);
    while (headers.length && headers.at(-1) === "") headers.pop();
    const rows = cells.slice(1).map((r) => headers.map((_, i) => cellValue(r[i])));
    while (rows.length && rows.at(-1).every((v) => v === "")) rows.pop();
    const sourceDigest = inputDigest(headers, rows);
    return frozen({ bindingDigest: digest(b), sourceDigest, headers, rows,
      cells: cells.slice(0, rows.length + 1), title: sheet.properties.title });
  }
  async ingest(options) {
    const snapshot = await this.read(options);
    return { ...ingestRows(snapshot.headers, snapshot.rows), bindingDigest: snapshot.bindingDigest };
  }
  async writeback(expectedInputDigest, statuses, { signal } = {}) {
    demand(Array.isArray(statuses) && statuses.length > 0 && statuses.length <= 500,
      "SHEET_WRITE_BOUND_INVALID");
    const before = await this.read({ signal });
    const plans = planSheetWriteback({ expectedInputDigest,
      currentHeaders: before.headers, currentRows: before.rows, statuses });
    const b = this.#binding;
    const requests = [];
    const expected = [];
    for (const plan of plans) {
      for (const [column, value] of Object.entries(plan.values)) {
        const col = before.headers.indexOf(column);
        const row = plan.row - 1;
        demand(col >= 0 && row > 0 && row < before.cells.length, "SHEET_WRITE_RANGE_DENIED");
        writableCell(before.cells[row]?.[col], value);
        expected.push({ row, col, value });
        requests.push({ updateCells: { start: { sheetId: b.sheetId,
          rowIndex: b.headerRow + plan.row - 2, columnIndex: col },
          rows: [{ values: [{ userEnteredValue: { stringValue: value } }] }],
          fields: "userEnteredValue" } });
      }
    }
    demand(requests.length > 0 && requests.length <= 3500, "SHEET_WRITE_BOUND_INVALID");
    let acknowledged = false;
    try {
      const response = await this.#http.request(`/v4/spreadsheets/${b.spreadsheetId}:batchUpdate`, {
        method: "POST", signal, body: { requests } });
      acknowledged = response.data?.spreadsheetId === b.spreadsheetId;
    } catch (error) {
      if (!error.outcomeUnknown) throw error;
      // Read the destination, never blindly repeat an uncertain write.
    }
    let after;
    try { after = await this.read({ signal }); }
    catch { throw failure("SHEET_WRITE_RECONCILIATION_REQUIRED"); }
    demand(after.sourceDigest === before.sourceDigest &&
      after.bindingDigest === before.bindingDigest, "SHEET_CHANGED_DURING_WRITE");
    for (const { row, col, value } of expected) {
      const entered = after.cells[row]?.[col]?.userEnteredValue;
      // Google may omit ExtendedValue entirely after a successful clear.
      // Numeric zero, false and formula output are not an empty string.
      const blank = entered == null || Object.keys(entered).length === 0 ||
        (Object.keys(entered).length === 1 && entered.stringValue === "");
      demand(value === "" ? blank : entered?.stringValue === value,
        "SHEET_WRITE_READBACK_MISMATCH");
    }
    return frozen({ verified: true, mutationAcknowledged: acknowledged,
      sourceDigest: after.sourceDigest, bindingDigest: after.bindingDigest,
      cellsVerified: expected.length, transactionalCompareAndSwap: false });
  }
}
module.exports = { GoogleSheetsConnector };
