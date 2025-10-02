export default {
  testEnvironment: 'jsdom',
  setupFiles: [
    '<rootDir>/test/setup/polyfills.js',
    'fake-indexeddb/auto'
  ],
  
  // Map ESM imports that your terminal.js does
  moduleNameMapper: {
    '^@rails/actioncable$': '<rootDir>/__mocks__/@rails/actioncable.js',
    '^/pq/oqsClient.js$': '<rootDir>/__mocks__/oqsClient.js'
  },
  transform: {}
};