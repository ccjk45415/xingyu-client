import {DurableObject} from 'cloudflare:workers';
import {createAnnouncementHub} from './announcements-core.mjs';
export class AnnouncementHub extends createAnnouncementHub(DurableObject) {}
