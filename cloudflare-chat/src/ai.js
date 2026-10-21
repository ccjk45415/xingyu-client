import {DurableObject} from 'cloudflare:workers';
import {createAiHub} from './ai-core.mjs';
export class AiDraftHub extends createAiHub(DurableObject){}
