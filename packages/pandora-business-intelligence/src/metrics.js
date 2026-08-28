'use strict';
const { createMetricDefinition } = require('./contracts.js');

const BUILTIN_METRICS = Object.freeze([
  {key:'completed_booking',event:'booking_completed',aggregation:'count',unit:'count'},
  {key:'completed_order',event:'order_completed',aggregation:'count',unit:'count'},
  {key:'checkout_conversion_rate',event:'checkout_completed',denominatorEvent:'checkout_started',aggregation:'rate',unit:'percent',minimumSampleSize:20},
  {key:'lead_submitted',event:'lead_submitted',aggregation:'count',unit:'count'},
  {key:'signup_completed',event:'signup_completed',aggregation:'count',unit:'count'},
  {key:'active_user',event:'session_started',aggregation:'unique_count',unit:'count'},
  {key:'returning_customer',event:'customer_returned',aggregation:'unique_count',unit:'count'},
  {key:'revenue',event:'revenue_recorded',aggregation:'sum',unit:'currency',property:'amount'},
  {key:'average_order_value',event:'order_completed',aggregation:'average',unit:'currency',property:'amount'},
  {key:'support_ticket_count',event:'support_ticket_created',aggregation:'count',unit:'count'},
  {key:'manual_hours_saved',event:'workflow_completed',aggregation:'sum',unit:'hours',property:'manual_hours_saved'},
  {key:'workflow_completion',event:'workflow_completed',aggregation:'count',unit:'count'},
  {key:'time_to_complete',event:'workflow_completed',aggregation:'average',unit:'seconds',property:'duration_seconds'},
].map((metric) => createMetricDefinition(metric)));

class BusinessMetricRegistry {
  constructor(seed = BUILTIN_METRICS) {
    this.metrics = new Map();
    for (const metric of seed) this.register(metric);
  }
  register(definition) {
    const metric = createMetricDefinition(definition);
    if (this.metrics.has(metric.key)) throw new Error(`metric already registered: ${metric.key}`);
    this.metrics.set(metric.key, metric);
    return metric;
  }
  get(key) { return this.metrics.get(key) ?? null; }
  require(key) {
    const metric = this.get(key);
    if (!metric) throw new Error(`unknown metric: ${key}`);
    return metric;
  }
  list() { return [...this.metrics.values()]; }
}
module.exports = { BUILTIN_METRICS, BusinessMetricRegistry };
