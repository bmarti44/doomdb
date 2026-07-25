import {selfTestDbOutput} from './lib/db-output.mjs';

selfTestDbOutput();
process.stdout.write('DB_OUTPUT_HELPER|PASS|wide_linesize=32767|wrap_normalization=1|adversarial_self_test=1\n');
