import {DurableObject} from 'cloudflare:workers';
import {createDmHub} from './dm-core.mjs';
export class DmHub extends createDmHub(DurableObject) {}
