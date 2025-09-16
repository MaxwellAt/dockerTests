import http from 'k6/http';
import { check, sleep } from 'k6';

const TOTAL_USERS_TO_CREATE = 5000;
const MAX_VUS = 500;

export let options = {
    setupTimeout: '10m',
    stages: [
        { duration: '3m', target: MAX_VUS },
    ],
    thresholds: {
        'http_req_duration{name:DeleteUser}': ['avg<500'],
        'http_req_failed{name:DeleteUser}': ['rate<0.01'],
        'checks{name:DeleteUserChecks}': ['rate>0.99'],
    }
};

const BASE_URL = __ENV.BASE_URL || 'http://localhost:3000';
const BUFFER_DELAY = 10;

export function setup() {
    console.log(`Iniciando setup: criando ${TOTAL_USERS_TO_CREATE} usuários...`);

    const batchSize = 100;
    let allUserIds = [];
    for (let i = 0; i < TOTAL_USERS_TO_CREATE; i += batchSize) {
        const requests = [];
        for (let j = 0; j < batchSize && (i + j) < TOTAL_USERS_TO_CREATE; j++) {
            const userIndex = i + j + 1;
            const now = Date.now();
            const payload = JSON.stringify({
                name: `Test User ${userIndex}`,
                username: `test_user_${userIndex}_${now}`,
                email: `test_user_${userIndex}_${now}@mail.com`,
            });
            requests.push({
                method: 'POST',
                url: `${BASE_URL}/users`,
                body: payload,
                params: {
                    headers: { 'Content-Type': 'application/json' },
                    tags: { name: 'CreateUser-Setup' },
                }
            });
        }
        const responses = http.batch(requests);
        const batchUserIds = responses
            .map(r => {
                try {
                    const direct = r.json && r.json('id');
                    if (direct) return direct;
                } catch (_) {}
                const loc = (r.headers && (r.headers.Location || r.headers['Location'])) || null;
                if (loc) {
                    const parts = loc.split('/').filter(Boolean);
                    return parts[parts.length - 1] || null;
                }
                try {
                    const body = r.json ? r.json() : JSON.parse(r.body || '{}');
                    if (body?.id) return body.id;
                    if (body?.data?.id) return body.data.id;
                    if (body?.user?.id) return body.user.id;
                } catch (_) {}
                return null;
            })
            .filter(id => id);
        allUserIds.push(...batchUserIds);
    }

    console.log('------------------------------------------------------');
    console.log(`Setup concluído: ${allUserIds.length} usuários criados.`);

    console.log(`Dividindo ${allUserIds.length} IDs em ${MAX_VUS} pacotes de trabalho...`);
    const usersPerVU = Math.ceil(allUserIds.length / MAX_VUS);
    const vuData = {};
    for (let i = 0; i < MAX_VUS; i++) {
        const vuId = i + 1;
        const startIndex = i * usersPerVU;
        const endIndex = startIndex + usersPerVU;
        const userSlice = allUserIds.slice(startIndex, endIndex);
        vuData[vuId] = userSlice;
    }

    console.log(`Aguardando buffer de ${BUFFER_DELAY}s antes de iniciar VUs...`);
    sleep(BUFFER_DELAY);
    console.log('Iniciando teste de DELETE agora.');
    console.log('------------------------------------------------------');

    return vuData;
}

export function teardown(data) {
    console.log('Teste de 3 minutos concluído.');
}

export default function (data) {
    const myUserIds = data[__VU];

    if (!myUserIds || __ITER >= myUserIds.length) {
        return;
    }

    const userIdToDelete = myUserIds[__ITER];

    const res = http.del(`${BASE_URL}/users/${userIdToDelete}/`, null, {
        tags: { name: 'DeleteUser' },
    });

    check(res, {
        'DELETE status é 200 ou 204': (r) => [200, 204].includes(r.status),
        'DELETE < 500ms': (r) => r.timings.duration < 500,
    }, { name: 'DeleteUserChecks' });
}
