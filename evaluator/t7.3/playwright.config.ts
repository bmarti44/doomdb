import {defineConfig,devices} from '@playwright/test';
export default defineConfig({testDir:'./tests',forbidOnly:true,retries:0,workers:1,updateSnapshots:'none',reporter:[['json',{outputFile:'/tmp/t7.3-playwright-results.json'}]],use:{...devices['Desktop Chrome'],viewport:{width:1280,height:720},locale:'en-US',timezoneId:'UTC'},projects:[{name:'chromium',use:{browserName:'chromium'}}]});

