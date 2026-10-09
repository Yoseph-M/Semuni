const path = require('path');

module.exports = {
  moduleFileExtensions: ['js', 'json', 'ts'],
  rootDir: path.resolve(__dirname),
  testRegex: '.*\\.spec\\.ts$',
  transform: {
    '^.+\\.(t|j)s$': path.resolve(__dirname, '../../backend/node_modules/ts-jest'),
  },
  testEnvironment: 'node',
};
