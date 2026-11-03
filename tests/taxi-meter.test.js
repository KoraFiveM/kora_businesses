const fs = require('node:fs'), vm = require('node:vm'), assert = require('node:assert/strict'), path = require('node:path');
const html = (name) => path.join(__dirname, '..', 'jobs', 'taxi', 'html', name);
const elements = new Map(), events = {}, posts = [];
function node(key) {
    if (!elements.has(key)) elements.set(key, { style: {}, textContent: '', addEventListener: (event, fn) => events[key + ':' + event] = fn });
    return elements.get(key);
}
vm.runInNewContext(fs.readFileSync(html('meter.js'), 'utf8'), {
    document: { getElementById: node, querySelector: node }, window: { addEventListener: (event, fn) => events[event] = fn },
    fetch: (url, options) => { posts.push({ url, body: JSON.parse(options.body) }); return Promise.resolve(); },
    GetParentResourceName: () => 'kora_businesses', Number, JSON,
});
assert.equal(posts[0].url, 'https://kora_businesses/meterReady');
events.message({ data: { action: 'meterState', visible: true, running: true, meterData: { currentFare: 250, distanceTraveled: 2, defaultPrice: 125 } } });
assert.equal(node('.container').style.display, 'block'); assert.equal(node('total-price').textContent, '$ 250.00'); assert.equal(node('total-distance').textContent, '2.00 mi');
events['.toggle-meter-btn:click'](); assert.equal(posts[1].url, 'https://kora_businesses/enableMeter'); assert.equal(posts[1].body.enabled, false); assert.deepEqual(Object.keys(posts[1].body), ['enabled']);
events.message({ data: { action: 'meterState', visible: false, running: false, meterData: { currentFare: NaN } } });
assert.equal(node('.container').style.display, 'none'); assert.equal(node('total-price').textContent, '$ 0.00');
const remote = (fs.readFileSync(html('meter.html'), 'utf8').match(/https:\/\/[^\/"']+/g) || []).filter(u => u !== 'https://cfx-nui-kora_theme');
assert.deepEqual(remote, [], 'meter must not need CDN scripts (only kora_theme NUI assets allowed)');
const css = fs.readFileSync(html('meter.css'), 'utf8'), fonts = css.match(/font-family:[^;]+/g) || [];
assert.ok(fonts.length > 0, 'meter.css must declare fonts');
for (const f of fonts) assert.equal(f, 'font-family: var(--font-sans, Arial, sans-serif)', 'meter fonts must follow kora_theme --font-sans with the Arial fallback');
assert.ok(css.trimStart().startsWith(':root'), 'meter.css must start with a rule, not stray text');
console.log('taxi meter NUI: 13 assertions passed');
