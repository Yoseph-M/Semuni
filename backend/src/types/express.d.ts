// `export {}` keeps this file a module so `declare module 'express'` performs
// module *augmentation* rather than declaring a brand-new ambient module.
export {};

declare module 'express' {
  export interface Request {
    requestId?: string;
  }
}
