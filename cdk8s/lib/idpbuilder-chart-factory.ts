import { App, Chart } from 'cdk8s';
import { ApplicationConfig, ChartConstructor } from './idpbuilder-types';

/**
 * Factory for creating CDK8s charts with dependency injection
 */
export class IdpBuilderChartFactory {
  private static chartConstructors = new Map<string, ChartConstructor>();
  private static dependencyCache = new Map<string, Chart>();
  
  /**
   * Register a chart constructor with the factory
   */
  static register(name: string, constructor: ChartConstructor): void {
    this.chartConstructors.set(name, constructor);
  }
  
  /**
   * Create a chart instance with resolved dependencies.
   * Returns undefined if the config has no chart (e.g., skipSynthesis apps).
   */
  static async createChart(
    app: App,
    config: ApplicationConfig
  ): Promise<Chart | undefined> {
    // Skip chart creation if no chart is defined (e.g., backstage-templates)
    if (!config.chart) {
      return undefined;
    }

    // Clear dependency cache for each application
    this.dependencyCache.clear();

    // Resolve dependencies first
    const dependencies = await this.resolveDependencies(config.dependencies);

    // Get the chart constructor
    const ChartClass = this.chartConstructors.get(config.chart.type);
    if (!ChartClass) {
      throw new Error(`Chart type '${config.chart.type}' not registered. ` +
        `Available types: ${Array.from(this.chartConstructors.keys()).join(', ')}`);
    }

    // Merge props with resolved dependencies
    const chartProps = {
      ...config.chart.props,
      ...dependencies
    };

    // Create and return the chart instance
    // Use 'install' as the chart ID to generate install.yaml
    return new ChartClass(app, 'install', chartProps);
  }
  
  /**
   * Resolve chart dependencies
   */
  private static async resolveDependencies(
    dependencies?: ApplicationConfig['dependencies']
  ): Promise<Record<string, Chart>> {
    if (!dependencies) {
      return {};
    }
    
    const resolved: Record<string, Chart> = {};
    
    for (const [depName, depConfig] of Object.entries(dependencies)) {
      // Check cache first
      const cacheKey = `${depConfig.type}-${JSON.stringify(depConfig.props || {})}`;
      if (this.dependencyCache.has(cacheKey)) {
        resolved[depName] = this.dependencyCache.get(cacheKey)!;
        continue;
      }
      
      // Get the dependency constructor
      const DepClass = this.chartConstructors.get(depConfig.type);
      if (!DepClass) {
        throw new Error(`Dependency chart type '${depConfig.type}' not registered`);
      }
      
      // Create a temporary app for the dependency
      const tempApp = new App({
        outdir: 'dist/temp',
      });
      
      // Create the dependency instance
      const depInstance = new DepClass(
        tempApp,
        `${depName}-dep`,
        depConfig.props
      );
      
      // Cache and store
      this.dependencyCache.set(cacheKey, depInstance);
      resolved[depName] = depInstance;
    }
    
    return resolved;
  }
  
  /**
   * Get all registered chart types
   */
  static getRegisteredTypes(): string[] {
    return Array.from(this.chartConstructors.keys());
  }
  
  /**
   * Check if a chart type is registered
   */
  static isRegistered(type: string): boolean {
    return this.chartConstructors.has(type);
  }
  
  /**
   * Clear all registrations (useful for testing)
   */
  static clear(): void {
    this.chartConstructors.clear();
    this.dependencyCache.clear();
  }
}