# CDK8s CI/CD Integration Guide

This guide explains how to integrate CDK8s synthesis optimizations into your CI/CD pipelines for maximum performance and efficiency.

## Table of Contents

1. [Overview](#overview)
2. [GitHub Actions](#github-actions)
3. [GitLab CI](#gitlab-ci)
4. [Jenkins](#jenkins)
5. [ArgoCD Integration](#argocd-integration)
6. [Optimization Strategies](#optimization-strategies)
7. [Caching Strategies](#caching-strategies)
8. [Performance Monitoring](#performance-monitoring)

## Overview

### Benefits of Optimized CI/CD

- **Faster builds**: 60s → 15s for full synthesis
- **Selective builds**: Only synthesize changed charts
- **Parallel processing**: Utilize multiple cores
- **Smart caching**: Reuse compiled TypeScript
- **Fail fast**: Early detection of issues

### Key Principles

1. **Pre-compile TypeScript** in early stages
2. **Cache aggressively** but invalidate smartly
3. **Parallelize** independent operations
4. **Fail fast** on compilation errors
5. **Monitor performance** trends

## GitHub Actions

### Basic Optimized Workflow

```yaml
name: CDK8s CI/CD

on:
  push:
    branches: [main]
  pull_request:
    branches: [main]

jobs:
  analyze:
    runs-on: ubuntu-latest
    outputs:
      affected-charts: ${{ steps.analyze.outputs.charts }}
    steps:
      - uses: actions/checkout@v3
        with:
          fetch-depth: 0  # Need full history for git diff

      - name: Setup Node.js
        uses: actions/setup-node@v3
        with:
          node-version: '18'
          cache: 'npm'

      - name: Install dependencies
        run: npm ci

      - name: Analyze dependencies
        run: npm run analyze:deps

      - name: Detect changed files
        id: changed-files
        uses: tj-actions/changed-files@v35
        with:
          files: |
            charts/**/*.ts
            lib/**/*.ts
            main.ts

      - name: Determine affected charts
        id: analyze
        run: |
          if [ "${{ steps.changed-files.outputs.any_changed }}" == "true" ]; then
            CHARTS=$(echo "${{ steps.changed-files.outputs.all_changed_files }}" | \
              xargs -I {} basename {} .ts | \
              paste -sd "," -)
            echo "charts=$CHARTS" >> $GITHUB_OUTPUT
          else
            echo "charts=" >> $GITHUB_OUTPUT
          fi

  compile:
    runs-on: ubuntu-latest
    needs: analyze
    steps:
      - uses: actions/checkout@v3

      - name: Setup Node.js
        uses: actions/setup-node@v3
        with:
          node-version: '18'
          cache: 'npm'

      - name: Install dependencies
        run: npm ci

      - name: Cache compiled output
        uses: actions/cache@v3
        with:
          path: |
            .build
            dist/js
          key: ${{ runner.os }}-compile-${{ hashFiles('**/*.ts') }}
          restore-keys: |
            ${{ runner.os }}-compile-

      - name: Fast compile with esbuild
        run: npm run compile:fast

      - name: Upload compiled artifacts
        uses: actions/upload-artifact@v3
        with:
          name: compiled-output
          path: .build/

  synthesize:
    runs-on: ubuntu-latest
    needs: [analyze, compile]
    strategy:
      matrix:
        chunk: [1, 2, 3, 4]  # Parallel synthesis
    steps:
      - uses: actions/checkout@v3

      - name: Setup Node.js
        uses: actions/setup-node@v3
        with:
          node-version: '18'
          cache: 'npm'

      - name: Install dependencies
        run: npm ci

      - name: Download compiled output
        uses: actions/download-artifact@v3
        with:
          name: compiled-output
          path: .build/

      - name: Synthesize
        run: |
          if [ -n "${{ needs.analyze.outputs.affected-charts }}" ]; then
            # Selective synthesis for PRs
            npm run synth:selective -- --charts ${{ needs.analyze.outputs.affected-charts }}
          else
            # Fast full synthesis for main branch
            npm run synth:fast
          fi

      - name: Upload manifests
        uses: actions/upload-artifact@v3
        with:
          name: k8s-manifests-${{ matrix.chunk }}
          path: dist/

  validate:
    runs-on: ubuntu-latest
    needs: synthesize
    steps:
      - uses: actions/checkout@v3

      - name: Download all manifests
        uses: actions/download-artifact@v3
        with:
          pattern: k8s-manifests-*
          merge-multiple: true
          path: dist/

      - name: Validate manifests
        run: |
          for file in dist/*.yaml; do
            echo "Validating $file"
            kubectl apply --dry-run=client -f "$file"
          done

      - name: Run security scanning
        uses: aquasecurity/trivy-action@master
        with:
          scan-type: 'config'
          scan-ref: 'dist/'
```

### Advanced PR Workflow

```yaml
name: PR Validation

on:
  pull_request:
    types: [opened, synchronize]

jobs:
  smart-synthesis:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3
        with:
          fetch-depth: 0

      - name: Get changed files
        id: changed
        run: |
          CHANGED_CHARTS=$(git diff --name-only origin/${{ github.base_ref }}...HEAD | \
            grep -E "charts/.*\.ts$" | \
            xargs -I {} basename {} .ts | \
            paste -sd "," - || echo "")
          echo "charts=$CHANGED_CHARTS" >> $GITHUB_OUTPUT

      - name: Setup and install
        if: steps.changed.outputs.charts != ''
        uses: actions/setup-node@v3
        with:
          node-version: '18'
          cache: 'npm'

      - name: Install dependencies
        if: steps.changed.outputs.charts != ''
        run: npm ci

      - name: Load dependency cache
        if: steps.changed.outputs.charts != ''
        uses: actions/cache@v3
        with:
          path: cdk8s-dependencies.json
          key: ${{ runner.os }}-deps-${{ hashFiles('charts/**/*.ts') }}

      - name: Analyze if needed
        if: steps.changed.outputs.charts != ''
        run: |
          if [ ! -f cdk8s-dependencies.json ]; then
            npm run analyze:deps
          fi

      - name: Selective synthesis
        if: steps.changed.outputs.charts != ''
        run: |
          npm run synth:selective -- \
            --charts ${{ steps.changed.outputs.charts }} \
            --include-deps

      - name: Comment PR
        if: steps.changed.outputs.charts != ''
        uses: actions/github-script@v6
        with:
          script: |
            const charts = '${{ steps.changed.outputs.charts }}'.split(',');
            const body = `### 🚀 Synthesis Complete
            
            **Charts synthesized:** ${charts.length}
            - ${charts.join('\n- ')}
            
            View the manifests in the workflow artifacts.`;
            
            github.rest.issues.createComment({
              issue_number: context.issue.number,
              owner: context.repo.owner,
              repo: context.repo.repo,
              body: body
            });
```

## GitLab CI

### Optimized `.gitlab-ci.yml`

```yaml
stages:
  - prepare
  - compile
  - synthesize
  - validate
  - deploy

variables:
  npm_config_cache: "$CI_PROJECT_DIR/.npm"
  NODE_OPTIONS: "--max-old-space-size=4096"

cache:
  key: ${CI_COMMIT_REF_SLUG}
  paths:
    - .npm/
    - node_modules/
    - .build/
    - cdk8s-dependencies.json

# Preparation stage
install:
  stage: prepare
  image: node:18
  script:
    - npm ci --cache .npm --prefer-offline
  artifacts:
    paths:
      - node_modules/
    expire_in: 1 hour

analyze-deps:
  stage: prepare
  image: node:18
  needs: ["install"]
  script:
    - npm run analyze:deps
  artifacts:
    paths:
      - cdk8s-dependencies.json
    expire_in: 1 week
  rules:
    - if: '$CI_PIPELINE_SOURCE == "merge_request_event"'
      changes:
        - charts/**/*.ts
        - lib/**/*.ts
    - if: '$CI_COMMIT_BRANCH == "main"'

# Compilation stage
compile-fast:
  stage: compile
  image: node:18
  needs: ["install"]
  script:
    - npm run compile:fast
  artifacts:
    paths:
      - .build/
      - dist/js/
    expire_in: 1 hour

# Synthesis stage - parallel jobs
.synthesis-template:
  stage: synthesize
  image: node:18
  needs: ["compile-fast", "analyze-deps"]
  artifacts:
    paths:
      - dist/
    expire_in: 1 week

synthesize-selective:
  extends: .synthesis-template
  script:
    - |
      if [ "$CI_PIPELINE_SOURCE" == "merge_request_event" ]; then
        CHANGED_CHARTS=$(git diff --name-only origin/$CI_MERGE_REQUEST_TARGET_BRANCH_NAME...HEAD | \
          grep -E "charts/.*\.ts$" | \
          xargs -I {} basename {} .ts | \
          paste -sd "," - || echo "")
        
        if [ -n "$CHANGED_CHARTS" ]; then
          npm run synth:selective -- --charts $CHANGED_CHARTS --include-deps
        else
          echo "No chart changes detected"
        fi
      fi
  rules:
    - if: '$CI_PIPELINE_SOURCE == "merge_request_event"'

synthesize-full:
  extends: .synthesis-template
  script:
    - npm run synth:fast
  rules:
    - if: '$CI_COMMIT_BRANCH == "main"'

# Validation stage
validate-manifests:
  stage: validate
  image: alpine/kubectl:latest
  needs: ["synthesize-selective", "synthesize-full"]
  script:
    - |
      for file in dist/*.yaml; do
        echo "Validating $file"
        kubectl apply --dry-run=client -f "$file"
      done
  rules:
    - if: '$CI_PIPELINE_SOURCE == "merge_request_event"'
    - if: '$CI_COMMIT_BRANCH == "main"'

security-scan:
  stage: validate
  image:
    name: aquasec/trivy:latest
    entrypoint: [""]
  needs: ["synthesize-selective", "synthesize-full"]
  script:
    - trivy config dist/
  rules:
    - if: '$CI_PIPELINE_SOURCE == "merge_request_event"'
    - if: '$CI_COMMIT_BRANCH == "main"'

# Deploy stage
deploy-argocd:
  stage: deploy
  image: argoproj/argocd:latest
  needs: ["validate-manifests", "security-scan"]
  script:
    - |
      # Copy manifests to ArgoCD repo
      git clone https://gitlab-ci-token:${CI_JOB_TOKEN}@${CI_SERVER_HOST}/${ARGOCD_REPO}
      cp -r dist/* ${ARGOCD_REPO}/manifests/
      cd ${ARGOCD_REPO}
      git add .
      git commit -m "Update manifests from pipeline ${CI_PIPELINE_ID}"
      git push
  rules:
    - if: '$CI_COMMIT_BRANCH == "main"'
```

## Jenkins

### Jenkinsfile with Optimizations

```groovy
pipeline {
    agent {
        kubernetes {
            yaml '''
apiVersion: v1
kind: Pod
spec:
  containers:
  - name: node
    image: node:18
    command:
    - cat
    tty: true
    resources:
      requests:
        memory: "2Gi"
        cpu: "2"
      limits:
        memory: "4Gi"
        cpu: "4"
'''
        }
    }

    options {
        buildDiscarder(logRotator(numToKeepStr: '10'))
        timeout(time: 30, unit: 'MINUTES')
        parallelsAlwaysFailFast()
    }

    environment {
        NODE_OPTIONS = '--max-old-space-size=4096'
        CHARTS_CHANGED = ''
    }

    stages {
        stage('Prepare') {
            parallel {
                stage('Install Dependencies') {
                    steps {
                        container('node') {
                            sh 'npm ci'
                        }
                    }
                }
                
                stage('Detect Changes') {
                    when {
                        changeRequest()
                    }
                    steps {
                        script {
                            def changes = sh(
                                script: """
                                git diff --name-only origin/${process.env.CHANGE_TARGET}...HEAD | \
                                grep -E "charts/.*\\.ts\$" | \
                                xargs -I {} basename {} .ts | \
                                paste -sd "," - || echo ""
                                """,
                                returnStdout: true
                            ).trim()
                            process.env.CHARTS_CHANGED = changes
                        }
                    }
                }
            }
        }

        stage('Compile') {
            steps {
                container('node') {
                    sh 'npm run compile:fast'
                    stash includes: '.build/**', name: 'compiled'
                }
            }
        }

        stage('Analyze Dependencies') {
            steps {
                container('node') {
                    sh 'npm run analyze:deps'
                    stash includes: 'cdk8s-dependencies.json', name: 'deps'
                }
            }
        }

        stage('Synthesize') {
            parallel {
                stage('PR Selective Synthesis') {
                    when {
                        allOf {
                            changeRequest()
                            expression { process.env.CHARTS_CHANGED != '' }
                        }
                    }
                    steps {
                        container('node') {
                            unstash 'compiled'
                            unstash 'deps'
                            sh """
                                npm run synth:selective -- \
                                    --charts ${process.env.CHARTS_CHANGED} \
                                    --include-deps
                            """
                        }
                    }
                }
                
                stage('Main Branch Synthesis') {
                    when {
                        branch 'main'
                    }
                    steps {
                        container('node') {
                            unstash 'compiled'
                            unstash 'deps'
                            sh 'npm run synth:fast'
                        }
                    }
                }
            }
        }

        stage('Validate') {
            steps {
                container('node') {
                    sh '''
                        for file in dist/*.yaml; do
                            echo "Validating $file"
                            kubectl apply --dry-run=client -f "$file"
                        done
                    '''
                }
            }
        }
    }

    post {
        always {
            archiveArtifacts artifacts: 'dist/**/*.yaml', allowEmptyArchive: true
            publishHTML([
                allowMissing: false,
                alwaysLinkToLastBuild: true,
                keepAll: true,
                reportDir: 'dist',
                reportFiles: 'index.html',
                reportName: 'Synthesized Manifests'
            ])
        }
        success {
            echo 'Synthesis completed successfully!'
        }
        failure {
            echo 'Synthesis failed!'
        }
    }
}
```

## ArgoCD Integration

### Optimized ArgoCD Application

```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: cdk8s-app
  namespace: argocd
spec:
  project: default
  source:
    repoURL: https://github.com/yourorg/cdk8s-manifests
    targetRevision: main
    path: dist
    directory:
      recurse: true
      jsonnet: {}
  destination:
    server: https://kubernetes.default.svc
    namespace: default
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
    syncOptions:
    - CreateNamespace=true
    retry:
      limit: 5
      backoff:
        duration: 5s
        factor: 2
        maxDuration: 3m
```

### CI/CD to ArgoCD Pipeline

```yaml
# .github/workflows/argocd-deploy.yml
name: Deploy to ArgoCD

on:
  push:
    branches: [main]

jobs:
  synthesize-and-deploy:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3
      
      - name: Setup Node.js
        uses: actions/setup-node@v3
        with:
          node-version: '18'
          cache: 'npm'
      
      - name: Install and compile
        run: |
          npm ci
          npm run compile:fast
      
      - name: Synthesize
        run: npm run synth:fast
      
      - name: Push to manifests repo
        env:
          MANIFESTS_REPO: ${{ secrets.MANIFESTS_REPO }}
          GITHUB_TOKEN: ${{ secrets.MANIFESTS_TOKEN }}
        run: |
          git config --global user.email "ci@example.com"
          git config --global user.name "CI Bot"
          
          git clone https://${GITHUB_TOKEN}@github.com/${MANIFESTS_REPO} manifests
          rm -rf manifests/dist/*
          cp -r dist/* manifests/dist/
          
          cd manifests
          git add .
          git commit -m "Update from ${GITHUB_SHA}" || exit 0
          git push
```

## Optimization Strategies

### 1. Dependency Caching

```yaml
# GitHub Actions example
- name: Cache dependencies
  uses: actions/cache@v3
  with:
    path: |
      ~/.npm
      node_modules
      .build
      cdk8s-dependencies.json
    key: ${{ runner.os }}-deps-${{ hashFiles('**/package-lock.json') }}-${{ hashFiles('**/*.ts') }}
    restore-keys: |
      ${{ runner.os }}-deps-${{ hashFiles('**/package-lock.json') }}-
      ${{ runner.os }}-deps-
```

### 2. Parallel Execution

```yaml
# Matrix strategy for parallel synthesis
strategy:
  matrix:
    chart-group:
      - "platform"
      - "applications"
      - "infrastructure"
      - "observability"
steps:
  - name: Synthesize chart group
    run: |
      npm run synth:selective -- \
        --dir "charts/${{ matrix.chart-group }}" \
        --include-deps
```

### 3. Incremental Builds

```bash
#!/bin/bash
# Smart build script

# Check if TypeScript files changed
if git diff --cached --name-only | grep -q "\.ts$"; then
  echo "TypeScript files changed, recompiling..."
  npm run compile:fast
else
  echo "No TypeScript changes, using cached compilation"
fi

# Always run synthesis (it will use compiled output)
npm run synth:fast
```

### 4. Fail-Fast Validation

```yaml
# Early validation stage
validate-typescript:
  runs-on: ubuntu-latest
  steps:
    - uses: actions/checkout@v3
    - name: Quick TypeScript check
      run: |
        npm ci
        npx tsc --noEmit
  # This job runs in parallel with others
```

## Caching Strategies

### 1. Multi-Level Cache

```yaml
# Level 1: NPM packages
- name: Cache NPM packages
  uses: actions/cache@v3
  with:
    path: ~/.npm
    key: ${{ runner.os }}-npm-${{ hashFiles('package-lock.json') }}

# Level 2: Node modules
- name: Cache node_modules
  uses: actions/cache@v3
  with:
    path: node_modules
    key: ${{ runner.os }}-modules-${{ hashFiles('package-lock.json') }}

# Level 3: Compiled output
- name: Cache compilation
  uses: actions/cache@v3
  with:
    path: .build
    key: ${{ runner.os }}-build-${{ hashFiles('**/*.ts') }}

# Level 4: Dependency analysis
- name: Cache dependencies
  uses: actions/cache@v3
  with:
    path: cdk8s-dependencies.json
    key: ${{ runner.os }}-deps-${{ hashFiles('charts/**/*.ts') }}
```

### 2. Smart Cache Invalidation

```bash
#!/bin/bash
# Invalidate cache based on changes

CACHE_KEY="build-cache"

# Add TypeScript files hash
TS_HASH=$(find . -name "*.ts" -type f -exec md5sum {} \; | sort | md5sum | cut -d' ' -f1)
CACHE_KEY="${CACHE_KEY}-ts-${TS_HASH}"

# Add package.json hash
PKG_HASH=$(md5sum package-lock.json | cut -d' ' -f1)
CACHE_KEY="${CACHE_KEY}-pkg-${PKG_HASH}"

echo "Cache key: ${CACHE_KEY}"
```

## Performance Monitoring

### 1. Build Time Tracking

```yaml
# GitHub Actions with timing
- name: Synthesis with timing
  run: |
    START_TIME=$(date +%s)
    npm run synth:fast
    END_TIME=$(date +%s)
    DURATION=$((END_TIME - START_TIME))
    
    echo "::notice::Synthesis completed in ${DURATION} seconds"
    
    # Send to monitoring
    curl -X POST ${{ secrets.METRICS_URL }} \
      -H "Content-Type: application/json" \
      -d "{\"metric\":\"synthesis_time\",\"value\":${DURATION},\"labels\":{\"branch\":\"${{ github.ref }}\"}}"
```

### 2. Grafana Dashboard

```json
{
  "dashboard": {
    "title": "CDK8s CI/CD Performance",
    "panels": [
      {
        "title": "Synthesis Time Trend",
        "targets": [
          {
            "expr": "avg(synthesis_time) by (branch)"
          }
        ]
      },
      {
        "title": "Cache Hit Rate",
        "targets": [
          {
            "expr": "rate(cache_hits) / rate(cache_attempts)"
          }
        ]
      },
      {
        "title": "Parallel Efficiency",
        "targets": [
          {
            "expr": "sum(synthesis_time) / max(synthesis_time)"
          }
        ]
      }
    ]
  }
}
```

### 3. Performance Regression Detection

```yaml
# Check for performance regression
- name: Check performance
  run: |
    CURRENT_TIME=$(cat synthesis_time.txt)
    BASELINE_TIME=$(curl -s ${{ secrets.METRICS_URL }}/baseline)
    
    if [ $(echo "$CURRENT_TIME > $BASELINE_TIME * 1.2" | bc) -eq 1 ]; then
      echo "::warning::Performance regression detected! Current: ${CURRENT_TIME}s, Baseline: ${BASELINE_TIME}s"
      exit 1
    fi
```

## Best Practices

### 1. Use Appropriate Strategies

- **PRs**: Selective synthesis with changed charts
- **Main branch**: Fast full synthesis
- **Release**: Full synthesis with validation
- **Hotfix**: Minimal selective synthesis

### 2. Optimize for Your Workflow

```yaml
# Different strategies for different triggers
on:
  pull_request:
    # Selective synthesis
  push:
    branches: [main]
    # Fast full synthesis
  release:
    types: [created]
    # Full synthesis with extensive validation
  workflow_dispatch:
    inputs:
      charts:
        description: 'Charts to synthesize (comma-separated)'
        # Manual selective synthesis
```

### 3. Monitor and Iterate

1. Track synthesis times
2. Monitor cache effectiveness
3. Analyze bottlenecks
4. Adjust parallelization
5. Optimize based on data

### 4. Fail Fast, Recover Quickly

```yaml
# Quick validation before expensive operations
jobs:
  quick-check:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3
      - run: |
          # Quick syntax check
          find . -name "*.ts" -exec node -c {} \;
    # This completes in seconds
  
  full-build:
    needs: quick-check
    # Expensive operations only after quick check
```
