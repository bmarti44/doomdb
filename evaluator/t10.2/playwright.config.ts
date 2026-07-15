import {defineConfig} from '@playwright/test';
export default defineConfig({testDir:'./tests',forbidOnly:true,retries:0,workers:1,updateSnapshots:'none',timeout:30000,reporter:[['json',{outputFile:'/tmp/t10.2-playwright-results.json'}]],use:{browserName:'chromium',locale:'en-US',timezoneId:'UTC',colorScheme:'dark',deviceScaleFactor:1,reducedMotion:'reduce'},projects:[{name:'chromium'}]});
