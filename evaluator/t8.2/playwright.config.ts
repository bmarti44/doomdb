import {defineConfig} from '@playwright/test';
export default defineConfig({testDir:'./tests',forbidOnly:true,retries:0,workers:1,updateSnapshots:'none',reporter:[['json',{outputFile:'/tmp/t8.2-playwright-results.json'}]],use:{browserName:'chromium',locale:'en-US',timezoneId:'UTC',colorScheme:'dark',deviceScaleFactor:1},projects:[{name:'chromium',use:{viewport:{width:1280,height:720}}}]});
