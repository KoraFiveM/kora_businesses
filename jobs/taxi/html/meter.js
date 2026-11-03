// Meter state is owned by the Lua client. Never submit amounts or payment requests from NUI.
const field = (id) => document.getElementById(id);
let running = false;
const post = (name, body) => fetch(`https://${GetParentResourceName()}/${name}`, {
    method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify(body)
});
window.addEventListener('message', ({ data }) => {
    if (!data || data.action !== 'meterState') return;
    document.querySelector('.container').style.display = data.visible ? 'block' : 'none';
    running = data.running === true;
    const meter = data.meterData || {};
    for (const [id, key, prefix, suffix] of [
        ['total-price', 'currentFare', '$ ', ''],
        ['total-price-per-100m', 'defaultPrice', '$ ', ''],
        ['total-distance', 'distanceTraveled', '', ' mi']
    ]) {
        const value = Number.isFinite(meter[key]) ? meter[key] : 0;
        field(id).textContent = prefix + value.toFixed(2) + suffix;
    }
    const label = document.querySelector('.toggle-meter-btn p');
    label.textContent = running ? 'Started' : 'Stopped';
    label.style.color = running ? 'rgb(51, 160, 37)' : 'rgb(231, 30, 37)';
});
document.querySelector('.toggle-meter-btn').addEventListener('click', () => {
    post('enableMeter', { enabled: !running }).catch(() => {});
});
post('meterReady', {}).catch(() => {});
