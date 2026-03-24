import { useState, useEffect } from 'react'
import './App.css'

// ─────────────────────────────────────────────────────────────────────────────
// DevSecOps 4-Cluster Dashboard
//
// tart 기반 4개 K8s 클러스터(platform/dev/staging/prod)의 상태를 시각화한다.
// Phase 4에서 각 클러스터의 Prometheus API와 연동하여 실제 메트릭으로 교체한다.
// ─────────────────────────────────────────────────────────────────────────────

const CLUSTERS = [
  {
    name: 'platform',
    role: '관리/관측',
    nodes: 3,
    services: ['Prometheus', 'Grafana', 'ArgoCD', 'Jenkins', 'Loki', 'Vault'],
    status: 'Healthy',
    pods: { running: 18, total: 18 },
  },
  {
    name: 'dev',
    role: '개발/테스트',
    nodes: 2,
    services: ['Istio', 'Cilium', 'Trivy Operator', 'HPA', 'Demo Apps'],
    status: 'Healthy',
    pods: { running: 12, total: 12 },
  },
  {
    name: 'staging',
    role: '스테이징',
    nodes: 2,
    services: ['Cilium', 'Trivy Operator'],
    status: 'Healthy',
    pods: { running: 6, total: 6 },
  },
  {
    name: 'prod',
    role: '운영',
    nodes: 3,
    services: ['Gatekeeper', 'Sealed Secrets', 'Velero', 'Harbor', 'Trivy Operator'],
    status: 'Healthy',
    pods: { running: 15, total: 15 },
  },
]

const SECURITY = {
  policies: [
    { name: 'block-latest-tag', cluster: 'prod', violations: 0, status: 'enforced' },
    { name: 'require-labels', cluster: 'prod', violations: 0, status: 'enforced' },
    { name: 'block-privileged', cluster: 'prod', violations: 0, status: 'enforced' },
  ],
  vulnerabilities: { critical: 0, high: 3, medium: 8 },
  lastScan: new Date().toISOString(),
}

const PIPELINE = [
  { name: 'Lint', status: 'passed', duration: '12s' },
  { name: 'Test', status: 'passed', duration: '28s' },
  { name: 'Trivy Scan', status: 'passed', duration: '45s' },
  { name: 'Build', status: 'passed', duration: '1m 20s' },
  { name: 'Deploy → dev', status: 'passed', duration: '35s' },
  { name: 'Deploy → staging', status: 'pending', duration: '-' },
  { name: 'Deploy → prod', status: 'pending', duration: '-' },
]

function StatusBadge({ status }) {
  const colors = {
    Healthy: '#22c55e', Active: '#22c55e', passed: '#22c55e',
    enforced: '#22c55e', Warning: '#eab308', pending: '#6b7280',
    failed: '#ef4444',
  }
  return (
    <span style={{
      padding: '2px 10px', borderRadius: '12px', fontSize: '12px',
      fontWeight: 600, color: '#fff', background: colors[status] || '#6b7280',
    }}>
      {status}
    </span>
  )
}

function Card({ title, children }) {
  return <div className="card"><h3>{title}</h3>{children}</div>
}

function App() {
  const [time, setTime] = useState(new Date())
  useEffect(() => {
    const t = setInterval(() => setTime(new Date()), 1000)
    return () => clearInterval(t)
  }, [])

  const totalNodes = CLUSTERS.reduce((s, c) => s + c.nodes, 0)
  const totalPods = CLUSTERS.reduce((s, c) => s + c.pods.running, 0)

  return (
    <div className="dashboard">
      <header>
        <h1>DevSecOps Dashboard</h1>
        <div className="header-stats">
          <span>{CLUSTERS.length} clusters</span>
          <span>{totalNodes} nodes</span>
          <span>{totalPods} pods</span>
        </div>
        <span className="clock">{time.toLocaleTimeString()}</span>
      </header>

      <div className="grid">
        {CLUSTERS.map(c => (
          <Card key={c.name} title={`${c.name} — ${c.role}`}>
            <div className="cluster-header">
              <StatusBadge status={c.status} />
              <span className="node-count">{c.nodes} nodes</span>
              <span className="pod-count">{c.pods.running}/{c.pods.total} pods</span>
            </div>
            <div className="service-tags">
              {c.services.map(s => <span key={s} className="tag">{s}</span>)}
            </div>
          </Card>
        ))}

        <Card title="CI/CD Pipeline">
          <div className="pipeline-stages">
            {PIPELINE.map(s => (
              <div key={s.name} className="stage">
                <span className={`dot ${s.status}`} />
                <span>{s.name}</span>
                <span className="duration">{s.duration}</span>
              </div>
            ))}
          </div>
        </Card>

        <Card title="Security Posture">
          <div className="security-grid">
            <div className="vuln critical">
              <span className="count">{SECURITY.vulnerabilities.critical}</span>
              <span className="label">Critical</span>
            </div>
            <div className="vuln high">
              <span className="count">{SECURITY.vulnerabilities.high}</span>
              <span className="label">High</span>
            </div>
            <div className="vuln medium">
              <span className="count">{SECURITY.vulnerabilities.medium}</span>
              <span className="label">Medium</span>
            </div>
          </div>
          <div className="policy-list">
            {SECURITY.policies.map(p => (
              <div key={p.name} className="policy-row">
                <span>{p.name}</span>
                <StatusBadge status={p.status} />
              </div>
            ))}
          </div>
        </Card>
      </div>

      <footer>DevSecOps Homelab — tart 4-Cluster (10 VMs, 21 vCPU, 68 GB RAM)</footer>
    </div>
  )
}

export default App
