// Single source of truth for technology-based challenge topics.
// Defines the 8 flat topics aligned with the curriculum and roadmap.

const CHALLENGE_TOPICS = Object.freeze([
  Object.freeze({
    id: 'linux',
    title: 'Linux',
    shortTitle: 'Linux',
    fullName: 'Linux Troubleshooting',
    summary: 'System internals, process lifecycle, storage forensics, and kernel triage on live systems.',
    accent: '#8a63e8', // DevOps purple
    icon: `<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><polyline points="4 17 10 11 4 5"></polyline><line x1="12" y1="19" x2="20" y2="19"></line></svg>`,
  }),
  Object.freeze({
    id: 'shell',
    title: 'Shell Scripting',
    shortTitle: 'Shell',
    fullName: 'Shell Scripting Challenges',
    summary: 'Automation scripts, argument parsing, stream manipulation, error handling, and robust CLI tools.',
    accent: '#5fd39a', // Terminal mint/green
    icon: `<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><rect x="2" y="4" width="20" height="16" rx="3"></rect><path d="m7 15 4-4-4-4"></path><line x1="13" y1="15" x2="17" y2="15"></line></svg>`,
  }),
  Object.freeze({
    id: 'git',
    title: 'Git and GitHub',
    shortTitle: 'Git',
    fullName: 'Git & GitHub Challenges',
    summary: 'Branching strategies, merge conflict resolution, detached HEAD, history forensics, and remotes.',
    accent: '#f08080', // Git coral / muted red
    icon: `<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><circle cx="18" cy="18" r="3"></circle><circle cx="6" cy="6" r="3"></circle><path d="M18 6a3 3 0 0 0-3 3v6"></path><path d="M6 9v12"></path></svg>`,
  }),
  Object.freeze({
    id: 'docker',
    title: 'Docker',
    shortTitle: 'Docker',
    fullName: 'Docker Container Challenges',
    summary: 'Container runtime isolation, multi-stage builds, storage mounts, networking, and daemon triage.',
    accent: '#5ccfee', // Container cyan
    icon: `<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M4 10h4v4H4z"></path><path d="M10 10h4v4h-4z"></path><path d="M16 10h4v4h-4z"></path><path d="M10 4h4v4h-4z"></path><path d="M2 14c1.5 2 4 4 10 4s8.5-2 10-4"></path></svg>`,
  }),
  Object.freeze({
    id: 'kubernetes',
    title: 'Kubernetes',
    shortTitle: 'Kubernetes',
    fullName: 'Kubernetes Orchestration Challenges',
    summary: 'Pod failure triage, CrashLoopBackOff forensics, service discovery, config drift, and cluster debugging.',
    accent: '#7aa2f7', // Kubernetes steel blue
    icon: `<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><circle cx="12" cy="12" r="3"></circle><path d="M12 2v4"></path><path d="M12 18v4"></path><path d="m4.93 4.93 2.83 2.83"></path><path d="m16.24 16.24 2.83 2.83"></path><path d="M2 12h4"></path><path d="M18 12h4"></path><path d="m4.93 19.07 2.83-2.83"></path><path d="m16.24 7.76 2.83-2.83"></path></svg>`,
  }),
  Object.freeze({
    id: 'github-actions',
    title: 'CI/CD with GitHub Actions',
    shortTitle: 'GitHub Actions',
    fullName: 'GitHub Actions CI/CD Challenges',
    summary: 'Workflow orchestration, secrets management, artifact pipelines, matrix builds, and runner triage.',
    accent: '#c084fc', // GitHub Actions lavender
    icon: `<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><polygon points="12 2 15.09 8.26 22 9.27 17 14.14 18.18 21.02 12 17.77 5.82 21.02 7 14.14 2 9.27 8.91 8.26 12 2"></polygon></svg>`,
  }),
  Object.freeze({
    id: 'networking',
    title: 'Networking',
    shortTitle: 'Networking',
    fullName: 'Computer Networking Challenges',
    summary: 'Packet inspection, DNS resolution, port conflicts, socket states, and subnet routing diagnostics.',
    accent: '#2dd4bf', // Network teal
    icon: `<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><circle cx="12" cy="12" r="10"></circle><line x1="2" y1="12" x2="22" y2="12"></line><path d="M12 2a15.3 15.3 0 0 1 4 10 15.3 15.3 0 0 1-4 10 15.3 15.3 0 0 1-4-10 15.3 15.3 0 0 1 4-10z"></path></svg>`,
  }),
  Object.freeze({
    id: 'terraform',
    title: 'Terraform on AWS',
    shortTitle: 'Terraform',
    fullName: 'Terraform on AWS Challenges',
    summary: 'Infrastructure as code, state drift, provider locks, resource reconciliation, and module architecture.',
    accent: '#f4b860', // Cloud/Terraform amber
    icon: `<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="m8 3 4 8 5-5 5 15H2L8 3z"></path></svg>`,
  }),
]);

module.exports = {
  CHALLENGE_TOPICS,
};
