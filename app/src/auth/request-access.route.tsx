/**
 * Route module for /request-access, code-split for the same reason as the
 * triage screen: a signed-in user never loads the public application form, and
 * an applicant pays one small extra request for a page they visit once.
 */
export { RequestAccessScreen as Component } from './RequestAccessScreen'
