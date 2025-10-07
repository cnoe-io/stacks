import { IdpBuilderChartFactory } from './idpbuilder-chart-factory';
import * as glob from 'glob';
import * as path from 'path';

/**
 * Automatically register all chart classes found in the charts directory
 * This eliminates the need for manual imports and registrations
 */
export function autoRegisterCharts(): void {
  const startTime = Date.now();

  // Find all TypeScript files in charts directory that end with -chart.ts
  const chartPattern = path.join(__dirname, '../charts/**/*-chart.ts');
  const chartFiles = glob.sync(chartPattern);

  let registeredCount = 0;

  chartFiles.forEach(file => {
    try {
      // Import the module
      const module = require(file);

      // Find all exported classes that end with 'Chart'
      const chartClasses = Object.values(module).filter(
        (value) => typeof value === 'function' && value.name && value.name.endsWith('Chart')
      );

      // Register each chart class
      chartClasses.forEach((ChartClass: any) => {
        const chartName = ChartClass.name;

        // Skip if already registered (avoid duplicates)
        if (!IdpBuilderChartFactory.isRegistered(chartName)) {
          IdpBuilderChartFactory.register(chartName, ChartClass);
          registeredCount++;
        }
      });
    } catch (error) {
      console.warn(`Warning: Could not load chart from ${file}:`, error);
    }
  });

  const duration = Date.now() - startTime;
  console.log(`✓ Auto-registered ${registeredCount} charts in ${duration}ms`);
}

/**
 * Get statistics about registered charts
 */
export function getRegistrationStats(): {
  total: number;
  types: string[];
} {
  const types = IdpBuilderChartFactory.getRegisteredTypes();
  return {
    total: types.length,
    types: types.sort()
  };
}
